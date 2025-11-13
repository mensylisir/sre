#!/bin/bash
set -e
source 00-config-sign.sh
source lib-sign.sh

log "====== 开始生成所有集群证书 (定制化SANs策略) ======"

# --- 1. 创建工作区并获取主机名 ---
log "创建工作区目录: ${WORKSPACE_DIR}"
rm -rf "${WORKSPACE_DIR}"
mkdir -p "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}"

if [ ! -f "${HOSTS_FILE}" ]; then log "错误: ${HOSTS_FILE} 文件未找到!"; exit 1; fi
ALL_NODES_IP=($(cat ${HOSTS_FILE} | grep -vE '^\s*#|^\s*$' | sort -u))
log "从 ${HOSTS_FILE} 加载了 ${#ALL_NODES_IP[@]} 个节点 IP。"

log "--- 正在通过 SSH 动态获取所有节点的主机名 ---"
declare -A IP_TO_HOSTNAME
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=$(ssh ${SSH_OPTS} ${SSH_USER}@${node_ip} "hostname -s" 2>/dev/null)
    check_status "无法连接到节点 ${node_ip} 或获取其主机名！"
    IP_TO_HOSTNAME["${node_ip}"]="${hostname}"
    log "节点 ${node_ip} -> ${hostname}"
done
log "--- 主机名映射构建完成 ---"

# --- 2. 动态构建 SANs 列表 ---
log "--- 步骤 2: 根据节点角色动态构建 SANs 列表 ---"

# 构建 APIServer SANs: 包含所有 K8s 节点 (Master+Worker)
K8S_APISERVER_SANS_LIST=""
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[$node_ip]}
    K8S_APISERVER_SANS_LIST+=",IP:${node_ip},DNS:${hostname},DNS:${hostname}.cluster.local"
done
K8S_APISERVER_SANS="DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local${K8S_APISERVER_SANS_LIST}"
if [ -n "${K8S_APISERVER_EXTRA_SANS}" ]; then
    K8S_APISERVER_SANS+=",${K8S_APISERVER_EXTRA_SANS}"
fi
K8S_APISERVER_SANS=${K8S_APISERVER_SANS#,}
log "最终生成的 K8s APIServer SANs: ${K8S_APISERVER_SANS}"

# 构建 Etcd SANs: 包含所有 Master 和 Etcd 节点
CONTROL_PLANE_IPS=($(printf "%s\n%s\n" "${MASTER_NODES_IP[@]}" "${ETCD_NODES_IP[@]}" | sort -u))
ETCD_SANS_LIST=""
for node_ip in "${CONTROL_PLANE_IPS[@]}"; do
    hostname=${IP_TO_HOSTNAME[$node_ip]}
    ETCD_SANS_LIST+=",IP:${node_ip},DNS:${hostname}"
done
ETCD_COMMON_SANS="${ETCD_SANS_LIST}"
if [ -n "${ETCD_EXTRA_SANS}" ]; then
    ETCD_COMMON_SANS+=",${ETCD_EXTRA_SANS}"
fi
ETCD_COMMON_SANS=${ETCD_COMMON_SANS#,}
log "最终生成的 Etcd 通用 SANs: ${ETCD_COMMON_SANS}"

# --- 3. 生成所有 CA ---
log "--- 步骤 3: 生成所有 CA 证书 ---"
mkdir -p "cas"
generate_ca "cas/ca.key" "cas/ca.crt" "${K8S_CA_SUBJECT}"
generate_ca "cas/etcd-ca.key" "cas/etcd-ca.pem" "${ETCD_CA_SUBJECT}"
generate_ca "cas/front-proxy-ca.key" "cas/front-proxy-ca.crt" "${FRONT_PROXY_CA_SUBJECT}"

# --- 4. 为所有节点生成叶子证书 ---
log "--- 步骤 4: 生成所有叶子证书 ---"
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log "为节点 ${hostname} (${node_ip}) 生成证书..."
    
    # ================= 关键新增部分开始 =================
    # --- 为所有节点的 Kubelet 生成证书 ---
    # Subject 的 O (Organization) 字段必须是 "system:nodes"
    # Subject 的 CN (Common Name) 必须是 "system:node:<hostname>"
    # 这样 APIServer 才能正确识别出这是一个 Kubelet 并授予相应权限
    log "为节点 ${hostname} 的 Kubelet 生成客户端证书..."
    mkdir -p "${hostname}/kubernetes"
    generate_leaf_cert cas/ca.crt cas/ca.key \
        "${hostname}/kubernetes/kubelet.key" "${hostname}/kubernetes/kubelet.crt" \
        "/CN=system:node:${hostname}" "" "clientAuth" "system:nodes"
    
    if [[ " ${MASTER_NODES_IP[@]} " =~ " ${node_ip} " ]]; then
        log "为 Master 节点 ${hostname} 生成 Kubernetes 控制平面证书..."
        mkdir -p "${hostname}/kubernetes/pki"
        
        cp cas/ca.crt cas/ca.key cas/front-proxy-ca.crt cas/front-proxy-ca.key "${hostname}/kubernetes/pki/"

        generate_leaf_cert cas/ca.crt cas/ca.key \
            "${hostname}/kubernetes/pki/apiserver.key" "${hostname}/kubernetes/pki/apiserver.crt" \
            "/CN=kube-apiserver" "${K8S_APISERVER_SANS}" "serverAuth"

        generate_leaf_cert cas/ca.crt cas/ca.key \
            "${hostname}/kubernetes/pki/apiserver-kubelet-client.key" "${hostname}/kubernetes/pki/apiserver-kubelet-client.crt" \
            "/CN=kube-apiserver-kubelet-client" "" "clientAuth" "system:masters"

        generate_leaf_cert cas/front-proxy-ca.crt cas/front-proxy-ca.key \
            "${hostname}/kubernetes/pki/front-proxy-client.key" "${hostname}/kubernetes/pki/front-proxy-client.crt" \
            "/CN=front-proxy-client" "" "clientAuth"
        
        generate_leaf_cert cas/ca.crt cas/ca.key \
            "${hostname}/kubernetes/controller-manager.key" "${hostname}/kubernetes/controller-manager.crt" \
            "/CN=system:kube-controller-manager" "" "clientAuth"

        generate_leaf_cert cas/ca.crt cas/ca.key \
            "${hostname}/kubernetes/scheduler.key" "${hostname}/kubernetes/scheduler.crt" \
            "/CN=system:kube-scheduler" "" "clientAuth"
            
        generate_leaf_cert cas/ca.crt cas/ca.key \
            "${hostname}/kubernetes/admin.key" "${hostname}/kubernetes/admin.crt" \
            "/CN=kubernetes-admin" "" "clientAuth" "system:masters"

        generate_leaf_cert cas/ca.crt cas/ca.key \
            "${hostname}/kubernetes/kube-proxy.key" "${hostname}/kubernetes/kube-proxy.crt" \
            "/CN=system:kube-proxy" "" "clientAuth"

        log "生成 Service Account 密钥对..."
        openssl genrsa -out "${hostname}/kubernetes/pki/sa.key" 2048
        openssl rsa -in "${hostname}/kubernetes/pki/sa.key" -pubout -out "${hostname}/kubernetes/pki/sa.pub"
    fi
    if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]] || [[ " ${ETCD_NODES_IP[@]} " =~ " ${node_ip} " ]]; then
        log "为 Etcd 节点 ${hostname} 生成 Etcd 证书..."
        mkdir -p "${hostname}/etcd-ssl"
        cp cas/etcd-ca.pem cas/etcd-ca.key "${hostname}/etcd-ssl/"

        generate_leaf_cert cas/etcd-ca.pem cas/etcd-ca.key \
            "${hostname}/etcd-ssl/member-${hostname}-key.pem" "${hostname}/etcd-ssl/member-${hostname}.pem" \
            "/CN=etcd-member-${hostname}" "${ETCD_COMMON_SANS}" "serverAuth,clientAuth"

        generate_leaf_cert cas/etcd-ca.pem cas/etcd-ca.key \
            "${hostname}/etcd-ssl/admin-${hostname}-key.pem" "${hostname}/etcd-ssl/admin-${hostname}.pem" \
            "/CN=etcd-admin-${hostname}" "${ETCD_COMMON_SANS}" "serverAuth,clientAuth"

        generate_leaf_cert cas/etcd-ca.pem cas/etcd-ca.key \
            "${hostname}/etcd-ssl/node-${hostname}-key.pem" "${hostname}/etcd-ssl/node-${hostname}.pem" \
            "/CN=etcd-node-${hostname}" "${ETCD_COMMON_SANS}" "serverAuth,clientAuth"
    fi
done

log "====== 所有证书生成完毕！存放于 '${WORKSPACE_DIR}' 目录。 ======"