#!/bin/bash
set -e
source 00-config.sh
source lib.sh

STAGE="bundle"
ACTION_DESC="应用 ${STAGE} 阶段配置 (建立双CA信任)"

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
    log "同步 K8s 配置..."
    sync_to_remote "${hostname}/${STAGE}/kubernetes/" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/"
    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "同步 etcd SSL 配置..."
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
    fi
    log "同步 Kubelet 配置..."
    sync_to_remote "${hostname}/${STAGE}/kubelet.conf" "${node_ip}" "${REMOTE_KUBELET_CONF}"
    log "重启 kubelet 以应用所有变更..."
    run_remote "${node_ip}" "systemctl restart kubelet"
    wait_for_node_ready "${node_ip}"
    log "在 Master 节点 ${hostname} 上的变更已应用, 等待15秒观察控制平面 Pod 状态。"
    sleep 15
done

log "====== ${ACTION_DESC} 完成！集群现在处于双CA信任状态。 ======"