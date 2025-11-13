#!/bin/bash
set -e
source 00-config-replace.sh
source lib-replace.sh

ACTION_DESC="一键全量替换集群所有 CA 和证书"
log "====== 开始 ${ACTION_DESC} ======"

# --- 1. 准备工作 ---
log "--- 步骤 1: 创建工作区，拉取旧证书用于提取 SANs ---"
rm -rf "${WORKSPACE_DIR}"
mkdir -p "${WORKSPACE_DIR}/old_certs" "${WORKSPACE_DIR}/new_certs"
cd "${WORKSPACE_DIR}"

# 获取主机名映射
if [ ! -f "${HOSTS_FILE}" ]; then log "错误: ${HOSTS_FILE} 文件未找到!"; exit 1; fi
ALL_NODES_IP=($(cat ${HOSTS_FILE} | grep -vE '^\s*#|^\s*$' | sort -u))
declare -A IP_TO_HOSTNAME
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=$(ssh ${SSH_OPTS} ${SSH_USER}@${node_ip} "hostname -s" 2>/dev/null)
    check_status "无法连接到节点 ${node_ip} 或获取其主机名！"
    IP_TO_HOSTNAME["${node_ip}"]="${hostname}"
done

# 从第一个 Master/Etcd 节点拉取旧证书
FIRST_MASTER_IP=${MASTER_NODES_IP[0]}
FIRST_MASTER_HOSTNAME=${IP_TO_HOSTNAME[$FIRST_MASTER_IP]}
FIRST_ETCD_IP=${ETCD_NODES_IP[0]}
FIRST_ETCD_HOSTNAME=${IP_TO_HOSTNAME[$FIRST_ETCD_IP]}
log "从 ${FIRST_MASTER_HOSTNAME} 拉取旧证书用于提取 SANs..."
sync_from_remote "${FIRST_MASTER_IP}" "${REMOTE_K8S_DIR}/pki/" "old_certs/kubernetes/pki/"
sync_from_remote "${FIRST_ETCD_IP}" "${REMOTE_ETCD_DIR}/" "old_certs/etcd-ssl/"

# --- 2. 提取 SANs ---
log "--- 步骤 2: 从旧证书中智能提取 SANs ---"
extract_sans() { openssl x509 -in "$1" -noout -text | grep -A1 "Subject Alternative Name" | tail -n1 | sed 's/^[ \t]*//' | tr -d ' '; }
K8S_APISERVER_SANS=$(extract_sans "old_certs/kubernetes/pki/apiserver.crt")
ETCD_MEMBER_SANS=$(extract_sans "old_certs/etcd-ssl/member-${FIRST_ETCD_HOSTNAME}.pem")
ETCD_ADMIN_SANS=$(extract_sans "old_certs/etcd-ssl/admin-${FIRST_ETCD_HOSTNAME}.pem")
ETCD_NODE_SANS=$(extract_sans "old_certs/etcd-ssl/node-${FIRST_ETCD_HOSTNAME}.pem")
log "SANs 提取完成。"

# --- 3. 生成所有新 CA 和叶子证书 ---
log "--- 步骤 3: 在堡垒机上生成所有新证书和 kubeconfig ---"
# 生成新 CA
mkdir -p new_certs/cas
generate_ca "new_certs/cas/ca.key" "new_certs/cas/ca.crt" "${K8S_CA_SUBJECT}"
generate_ca "new_certs/cas/etcd-ca.key" "new_certs/cas/etcd-ca.pem" "${ETCD_CA_SUBJECT}"
generate_ca "new_certs/cas/front-proxy-ca.key" "new_certs/cas/front-proxy-ca.crt" "${FRONT_PROXY_CA_SUBJECT}"

# 为所有节点生成叶子证书和 kubeconfig
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    mkdir -p "new_certs/${hostname}/kubernetes/pki" "new_certs/${hostname}/etcd-ssl"

    # 生成 Kubelet 证书
    generate_leaf_cert "new_certs/cas/ca.crt" "new_certs/cas/ca.key" \
        "new_certs/${hostname}/kubernetes/kubelet.key" "new_certs/${hostname}/kubernetes/kubelet.crt" \
        "/O=system:nodes/CN=system:node:${hostname}" "" "clientAuth" "system:nodes"
    # 生成 kubelet.conf
    generate_kubeconfig "new_certs/${hostname}/kubernetes/kubelet.conf" "${CLUSTER_NAME}" "${CLUSTER_APISERVER_URL}" \
        "new_certs/cas/ca.crt" "system:node:${hostname}" "new_certs/${hostname}/kubernetes/kubelet.crt" "new_certs/${hostname}/kubernetes/kubelet.key"

    # 如果是 Master 节点
    if [[ " ${MASTER_NODES_IP[@]} " =~ " ${node_ip} " ]]; then
        # 生成 K8s 控制平面证书
        cp new_certs/cas/* "new_certs/${hostname}/kubernetes/pki/"
        generate_leaf_cert "new_certs/cas/ca.crt" "new_certs/cas/ca.key" "new_certs/${hostname}/kubernetes/pki/apiserver.key" "new_certs/${hostname}/kubernetes/pki/apiserver.crt" "/CN=kube-apiserver" "${K8S_APISERVER_SANS}" "serverAuth"
        generate_leaf_cert "new_certs/cas/ca.crt" "new_certs/cas/ca.key" "new_certs/${hostname}/kubernetes/pki/apiserver-kubelet-client.key" "new_certs/${hostname}/kubernetes/pki/apiserver-kubelet-client.crt" "/CN=kube-apiserver-kubelet-client" "" "clientAuth" "system:masters"
        generate_leaf_cert "new_certs/cas/front-proxy-ca.crt" "new_certs/cas/front-proxy-ca.key" "new_certs/${hostname}/kubernetes/pki/front-proxy-client.key" "new_certs/${hostname}/kubernetes/pki/front-proxy-client.crt" "/CN=front-proxy-client" "" "clientAuth"
        generate_leaf_cert "new_certs/cas/ca.crt" "new_certs/cas/ca.key" "new_certs/${hostname}/kubernetes/admin.key" "new_certs/${hostname}/kubernetes/admin.crt" "/CN=kubernetes-admin" "" "clientAuth" "system:masters"
        generate_leaf_cert "new_certs/cas/ca.crt" "new_certs/cas/ca.key" "new_certs/${hostname}/kubernetes/controller-manager.key" "new_certs/${hostname}/kubernetes/controller-manager.crt" "/CN=system:kube-controller-manager" "" "clientAuth"
        generate_leaf_cert "new_certs/cas/ca.crt" "new_certs/cas/ca.key" "new_certs/${hostname}/kubernetes/scheduler.key" "new_certs/${hostname}/kubernetes/scheduler.crt" "/CN=system:kube-scheduler" "" "clientAuth"
        openssl genrsa -out "new_certs/${hostname}/kubernetes/pki/sa.key" 2048 && openssl rsa -in "new_certs/${hostname}/kubernetes/pki/sa.key" -pubout -out "new_certs/${hostname}/kubernetes/pki/sa.pub"
        # 生成 K8s 控制平面 kubeconfig
        generate_kubeconfig "new_certs/${hostname}/kubernetes/admin.conf" "${CLUSTER_NAME}" "${CLUSTER_APISERVER_URL}" "new_certs/cas/ca.crt" "kubernetes-admin" "new_certs/${hostname}/kubernetes/admin.crt" "new_certs/${hostname}/kubernetes/admin.key"
        generate_kubeconfig "new_certs/${hostname}/kubernetes/controller-manager.conf" "${CLUSTER_NAME}" "${CLUSTER_APISERVER_URL}" "new_certs/cas/ca.crt" "system:kube-controller-manager" "new_certs/${hostname}/kubernetes/controller-manager.crt" "new_certs/${hostname}/kubernetes/controller-manager.key"
        generate_kubeconfig "new_certs/${hostname}/kubernetes/scheduler.conf" "${CLUSTER_NAME}" "${CLUSTER_APISERVER_URL}" "new_certs/cas/ca.crt" "system:kube-scheduler" "new_certs/${hostname}/kubernetes/scheduler.crt" "new_certs/${hostname}/kubernetes/scheduler.key"
    fi
    # 如果是 Etcd 节点
    if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]] || [[ " ${ETCD_NODES_IP[@]} " =~ " ${node_ip} " ]]; then
        # 生成 Etcd 证书
        cp new_certs/cas/etcd-ca.pem "new_certs/${hostname}/etcd-ssl/"
        cp new_certs/cas/etcd-ca.key "new_certs/${hostname}/etcd-ssl/"
        generate_leaf_cert "new_certs/cas/etcd-ca.pem" "new_certs/cas/etcd-ca.key" "new_certs/${hostname}/etcd-ssl/member-${hostname}-key.pem" "new_certs/${hostname}/etcd-ssl/member-${hostname}.pem" "/CN=etcd-member-${hostname}" "${ETCD_MEMBER_SANS}" "serverAuth,clientAuth"
        generate_leaf_cert "new_certs/cas/etcd-ca.pem" "new_certs/cas/etcd-ca.key" "new_certs/${hostname}/etcd-ssl/admin-${hostname}-key.pem" "new_certs/${hostname}/etcd-ssl/admin-${hostname}.pem" "/CN=etcd-admin-${hostname}" "${ETCD_ADMIN_SANS}" "serverAuth,clientAuth"
        generate_leaf_cert "new_certs/cas/etcd-ca.pem" "new_certs/cas/etcd-ca.key" "new_certs/${hostname}/etcd-ssl/node-${hostname}-key.pem" "new_certs/${hostname}/etcd-ssl/node-${hostname}.pem" "/CN=etcd-node-${hostname}" "${ETCD_NODE_SANS}" "serverAuth,clientAuth"
    fi
done
log "--- 所有新证书和 kubeconfig 生成完毕 ---"

confirm_action "${ACTION_DESC}"

# --- 4. 备份、分发并滚动重启 ---
log "--- 步骤 4: 备份远程节点，分发新证书并滚动重启服务 ---"
backup_ts=$(date +%Y%m%d-%H%M%S)

CONTROL_PLANE_IPS=($(printf "%s\n%s\n" "${MASTER_NODES_IP[@]}" "${ETCD_NODES_IP[@]}" | sort -u))
for node_ip in "${CONTROL_PLANE_IPS[@]}"; do
    hostname=${IP_TO_HOSTNAME[$node_ip]}
    log ">>> 正在滚动更新控制平面节点: ${hostname}"

    # 1. 停止该节点上的所有相关服务
    log "停止节点上的服务..."
    run_remote "${node_ip}" "systemctl stop kubelet etcd || true"

    # 2. 备份旧文件
    log "备份旧文件..."
    run_remote "${node_ip}" "mv ${REMOTE_K8S_DIR} ${REMOTE_K8S_DIR}.bak.${backup_ts} 2>/dev/null || true"
    run_remote "${node_ip}" "mv ${REMOTE_ETCD_DIR} ${REMOTE_ETCD_DIR}.bak.${backup_ts} 2>/dev/null || true"

    # 3. 分发所有新文件
    log "分发 K8s 文件..."
    sync_to_remote "new_certs/${hostname}/kubernetes/" "${node_ip}" "${REMOTE_K8S_DIR}/"
    run_remote "${node_ip}" "find ${REMOTE_K8S_DIR} -name '*.key' -exec chmod 600 {} \\;"
    
    log "分发 Etcd 文件..."
    sync_to_remote "new_certs/${hostname}/etcd-ssl/" "${node_ip}" "${REMOTE_ETCD_DIR}/"
    run_remote "${node_ip}" "find ${REMOTE_ETCD_DIR} \\( -name '*.key' -o -name '*-key.pem' \\) -exec chmod 600 {} \\;"
    
    # 4. 按顺序启动该节点上的服务
    log "按顺序启动服务..."
    if [[ " ${ETCD_NODES_IP[@]} " =~ " ${node_ip} " ]]; then
        run_remote "${node_ip}" "systemctl start etcd"
        log "等待 30 秒让 Etcd 实例稳定..." && sleep 30
    fi
    run_remote "${node_ip}" "systemctl start kubelet"
    
    # 5. 验证节点状态
    log "等待节点恢复..."
    # 此时集群可能还不可用，所以不能用 kubectl，只能等待
    sleep 60 
done

# 然后处理纯 Worker 节点
WORKER_NODES_IP=($(comm -23 <(printf "%s\n" "${ALL_NODES_IP[@]}" | sort -u) <(printf "%s\n" "${CONTROL_PLANE_IPS[@]}" | sort -u)))
for node_ip in "${WORKER_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[$node_ip]}
    log ">>> 正在滚动更新 Worker 节点: ${hostname}"

    run_remote "${node_ip}" "systemctl stop kubelet || true"
    run_remote "${node_ip}" "mv ${REMOTE_K8S_DIR} ${REMOTE_K8S_DIR}.bak.${backup_ts} 2>/dev/null || true"
    sync_to_remote "new_certs/${hostname}/kubernetes/" "${node_ip}" "${REMOTE_K8S_DIR}/"
    run_remote "${node_ip}" "find ${REMOTE_K8S_DIR} -name '*.key' -exec chmod 600 {} \\;"
    run_remote "${node_ip}" "systemctl start kubelet"
    sleep 15
done

# --- 5. 验证 ---
log "--- 步骤 5: 等待集群恢复并验证 ---"
export KUBECONFIG="${WORKSPACE_DIR}/new_certs/${FIRST_MASTER_HOSTNAME}/kubernetes/admin.conf"
log "等待所有节点变为 Ready... (可能需要几分钟)"
for node_ip in "${ALL_NODES_IP[@]}"; do
    wait_for_node_ready "${node_ip}"
done

log "集群状态检查:"
kubectl get nodes -o wide
kubectl get pods -n kube-system

log "====== ${ACTION_DESC} 完成！请手动执行深度验证脚本。 ======"