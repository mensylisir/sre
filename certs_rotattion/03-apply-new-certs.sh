#!/bin/bash
set -e
source 00-config.sh
source lib.sh

STAGE="new"
ACTION_DESC="应用 ${STAGE} 阶段叶子证书 (更换所有组件证书)"

cd "${WORKSPACE_DIR}" || { log "错误: 工作区目录 ${WORKSPACE_DIR} 不存在!"; exit 1; }

if [ ! -f "ip_hostname_map.txt" ]; then log "错误: ip_hostname_map.txt 未找到. 请先执行 01-prepare.sh"; exit 1; fi
declare -A IP_TO_HOSTNAME
while read -r ip host; do IP_TO_HOSTNAME["$ip"]="$host"; done < ip_hostname_map.txt

FIRST_MASTER_IP=${MASTER_NODES[0]}
if [ -z "${FIRST_MASTER_IP}" ]; then log "错误: MASTER_NODES 列表为空!"; exit 1; fi
FIRST_MASTER_HOSTNAME=${IP_TO_HOSTNAME[${FIRST_MASTER_IP}]}
KUBECONFIG_PATH="${WORKSPACE_DIR}/${FIRST_MASTER_HOSTNAME}/old/admin.conf"

if [ ! -f "${KUBECONFIG_PATH}" ]; then
    log "错误: 找不到用于 kubectl 的 kubeconfig 文件: ${KUBECONFIG_PATH}"
    exit 1
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
log "已将 KUBECONFIG 环境变量设置为: ${KUBECONFIG_PATH}"
log "测试 kubectl 连接..."
kubectl get nodes > /dev/null
if [ $? -ne 0 ]; then
    log "错误: 使用 ${KUBECONFIG_PATH} 无法连接到 Kubernetes 集群！请检查配置。"
    exit 1
fi

confirm_action "${ACTION_DESC}"
log "====== ${ACTION_DESC} 开始 ======"

MASTER_IPS_SORTED_SET=$(printf "%s\n" "${MASTER_NODES[@]}" | sort -u)
ETCD_IPS_SORTED_SET=$(printf "%s\n" "${ETCD_NODES[@]}" | sort -u)
ETCD_ONLY_NODES_IP=($(comm -13 <(echo "${MASTER_IPS_SORTED_SET}") <(echo "${ETCD_IPS_SORTED_SET}")))
CONTROL_PLANE_NODES=("${MASTER_NODES[@]}" "${ETCD_ONLY_NODES_IP[@]}")

log "--- 滚动更新控制平面节点 (Master 和 Etcd) 的叶子证书 ---"
for node_ip in "${CONTROL_PLANE_NODES[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log ">>> 处理控制平面节点: ${hostname} (${node_ip})"
    
    if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "该节点是 Master, 同步新的 Kubernetes 叶子证书..."
        rsync -avz -e "ssh ${SSH_OPTS}" --delete --exclude='ca.crt' --exclude='ca.key' --exclude='front-proxy-ca.crt' --exclude='front-proxy-ca.key' \
            "${hostname}/${STAGE}/kubernetes/pki/" ${SSH_USER}@${node_ip}:${REMOTE_K8S_CONFIG_DIR}/pki/
        if [ $? -ne 0 ]; then log "错误: 同步 K8s 叶子证书到 ${node_ip} 失败！"; exit 1; fi
    fi
     if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]] || [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "为节点 ${hostname} 同步全套 Etcd 叶子证书..."
        run_remote "${node_ip}" "mkdir -p ${REMOTE_ETCD_SSL_DIR}"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/admin-${hostname}.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/admin-${hostname}-key.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/member-${hostname}.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/member-${hostname}-key.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/node-${hostname}.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/node-${hostname}-key.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
    fi

    log "重启 kubelet 以应用新的叶子证书..."
    run_remote "${node_ip}" "systemctl restart kubelet"
    wait_for_node_ready "${node_ip}"
    
    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "节点证书已更换。等待30秒让 Etcd 集群稳定..."
        sleep 30
        
        local check_ca_path="${hostname}/bundle/etcd-ssl/ca.pem"
        local check_cert_path="${hostname}/new/etcd-ssl/admin-${hostname}.pem"
        local check_key_path="${hostname}/new/etcd-ssl/admin-${hostname}-key.pem"
        
        check_etcd_health "${node_ip}" "${check_ca_path}" "${check_cert_path}" "${check_key_path}"
    else
        log "节点证书已更换。等待15秒观察控制平面 Pod 状态..."
        sleep 15
    fi
done

log "====== ${ACTION_DESC} 完成！所有组件现在都使用由新CA签发的新证书。 ======"