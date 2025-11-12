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

confirm_action "${ACTION_DESC}"
log "====== ${ACTION_DESC} 开始 ======"

log "--- 滚动更新 Master 节点的叶子证书 ---"
for node_ip in "${MASTER_NODES[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log ">>> 处理 Master 节点: ${hostname} (${node_ip})"
    
    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "同步新的 etcd 叶子证书..."
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/admin-${hostname}.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/admin-${hostname}-key.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/member-${hostname}.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/member-${hostname}-key.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/node-${hostname}.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/node-${hostname}-key.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
    fi

    log "同步新的 Kubernetes 叶子证书..."
    rsync -avz -e "ssh ${SSH_OPTS}" --delete --exclude='ca.crt' --exclude='ca.key' --exclude='front-proxy-ca.crt' --exclude='front-proxy-ca.key' \
        "${hostname}/${STAGE}/kubernetes/pki/" ${SSH_USER}@${node_ip}:${REMOTE_K8S_CONFIG_DIR}/pki/
    if [ $? -ne 0 ]; then log "错误: 同步 K8s 叶子证书到 ${node_ip} 失败！"; exit 1; fi

    log "重启 kubelet 以应用新的叶子证书..."
    run_remote "${node_ip}" "systemctl restart kubelet"
    wait_for_node_ready "${node_ip}"
    log "在 Master 节点 ${hostname} 上的证书已更换, 等待15秒观察控制平面 Pod 状态。"
    sleep 15
done

log "====== ${ACTION_DESC} 完成！所有组件现在都使用由新CA签发的新证书。 ======"