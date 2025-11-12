#!/bin/bash
set -e
source 00-config.sh
source lib.sh

STAGE="new"
ACTION_DESC="应用 ${STAGE} 阶段最终配置 (移除旧CA信任)"

cd "${WORKSPACE_DIR}" || { log "错误: 工作区目录 ${WORKSPACE_DIR} 不存在!"; exit 1; }

if [ ! -f "ip_hostname_map.txt" ]; then log "错误: ip_hostname_map.txt 未找到. 请先执行 01-prepare.sh"; exit 1; fi
declare -A IP_TO_HOSTNAME
while read -r ip host; do IP_TO_HOSTNAME["$ip"]="$host"; done < ip_hostname_map.txt

MASTER_IPS_SORTED=$(printf "%s\n" "${MASTER_NODES[@]}" | sort)
ALL_IPS_SORTED=$(printf "%s\n" "${ALL_NODES[@]}" | sort)
WORKER_NODES_IP=($(comm -23 <(echo "${ALL_IPS_SORTED}") <(echo "${MASTER_IPS_SORTED}")))

confirm_action "${ACTION_DESC}"

log "====== ${ACTION_DESC} 开始 ======"

log "--- 滚动更新 Worker 节点 ---"
for node_ip in "${WORKER_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log ">>> 处理 Worker 节点: ${hostname} (${node_ip})"
    sync_to_remote "${hostname}/${STAGE}/kubelet.conf" "${node_ip}" "${REMOTE_KUBELET_CONF}"
    run_remote "${node_ip}" "systemctl restart kubelet"
    wait_for_node_ready "${node_ip}"
done

log "--- 滚动更新 Master 节点 ---"
for node_ip in "${MASTER_NODES[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log ">>> 处理 Master 节点: ${hostname} (${node_ip})"
    
    log "同步 K8s 的最终 CA 和 conf 文件..."
    sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/ca.crt" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/"
    sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/ca.key" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/"
    sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/front-proxy-ca.crt" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/"
    sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/front-proxy-ca.key" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/"
    sync_to_remote "${hostname}/${STAGE}/admin.conf" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/"
    sync_to_remote "${hostname}/${STAGE}/controller-manager.conf" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/"
    sync_to_remote "${hostname}/${STAGE}/scheduler.conf" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/"

    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "同步 etcd 的最终 CA..."
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/ca.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/ca-key.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
    fi

    log "同步 Kubelet 最终配置..."
    sync_to_remote "${hostname}/${STAGE}/kubelet.conf" "${node_ip}" "${REMOTE_KUBELET_CONF}"
    
    log "重启 kubelet 以完成最终切换..."
    run_remote "${node_ip}" "systemctl restart kubelet"
    wait_for_node_ready "${node_ip}"
    log "在 Master 节点 ${hostname} 上的最终配置已应用, 等待15秒观察控制平面 Pod 状态。"
    sleep 15
done

log "====== ${ACTION_DESC} 完成！CA 证书更换流程已全部结束。 ======"