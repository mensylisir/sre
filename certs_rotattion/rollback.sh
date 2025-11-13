#!/bin/bash
set -e
source 00-config.sh
source lib.sh

STAGE="old"
ACTION_DESC="!!! 灾难回滚 !!! 将所有节点恢复到初始 'old' 状态"

cd "${WORKSPACE_DIR}" || { log "错误: 工作区目录 ${WORKSPACE_DIR} 不存在!"; exit 1; }

if [ ! -f "ip_hostname_map.txt" ]; then log "错误: ip_hostname_map.txt 未找到. 请先执行 01-prepare.sh"; exit 1; fi
declare -A IP_TO_HOSTNAME
while read -r ip host; do IP_TO_HOSTNAME["$ip"]="$host"; done < ip_hostname_map.txt

confirm_action "${ACTION_DESC}"

log "====== 回滚操作开始 ======"

# 使用并行提高回滚速度
pids=()
ALL_NODES=($(cat ${HOSTS_FILE} | grep -vE '^\s*#|^\s*$' | sort -u))
for node_ip in "${ALL_NODES[@]}"; do
    (
        hostname=${IP_TO_HOSTNAME[${node_ip}]}
        log ">>> 正在回滚节点: ${hostname} (${node_ip})"
        
        # 回滚 Kubelet conf
        sync_to_remote "${hostname}/${STAGE}/kubelet.conf" "${node_ip}" "${REMOTE_KUBELET_CONF}"
        
        # 回滚 K8s conf
        if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]]; then
            sync_to_remote "${hostname}/${STAGE}/kubernetes/" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/"
        fi

        # 回滚 etcd conf
        if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
            sync_to_remote "${hostname}/${STAGE}/etcd-ssl/" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        fi
        
        run_remote "${node_ip}" "systemctl restart kubelet"
        log "节点 ${hostname} 回滚指令已发送。"
    ) &
    pids+=($!)
done

log "等待所有回滚任务完成..."
for pid in "${pids[@]}"; do
    wait $pid
done

log "====== 回滚操作完成！请手动检查集群状态。 ======"