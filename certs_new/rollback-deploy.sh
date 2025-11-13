#!/bin/bash
set -e
source 00-config-sign.sh
source lib-sign.sh

ACTION_DESC="!!! 灾难回滚 !!! 将所有受影响节点的配置恢复到分发前的状态"

log "====== 开始 ${ACTION_DESC} ======"

cd "${WORKSPACE_DIR}" || { log "错误: 工作区目录 '${WORKSPACE_DIR}' 不存在!"; exit 1; }

# 加载主机名映射
if [ ! -f "ip_hostname_map.txt" ]; then log "错误: ip_hostname_map.txt 未找到！"; exit 1; fi
declare -A IP_TO_HOSTNAME
while read -r ip host; do IP_TO_HOSTNAME["$ip"]="$host"; done < ip_hostname_map.txt

confirm_action "${ACTION_DESC}"

# --- 遍历所有节点并执行回滚 ---
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log ">>> 正在回滚节点: ${hostname} (${node_ip})"

    # --- 寻找最新的备份 ---
    # 这里的逻辑需要远程执行 ls 和 sort 来找到最新的备份目录
    log "在 ${hostname} 上查找最新的备份..."
    K8S_BACKUP_CMD="ls -dt ${REMOTE_K8S_DIR}.bak.* 2>/dev/null | head -n 1"
    ETCD_BACKUP_CMD="ls -dt ${REMOTE_ETCD_DIR}.bak.* 2>/dev/null | head -n 1"
    
    K8S_LATEST_BACKUP=$(ssh ${SSH_OPTS} ${SSH_USER}@${node_ip} "${K8S_BACKUP_CMD}")
    ETCD_LATEST_BACKUP=$(ssh ${SSH_OPTS} ${SSH_USER}@${node_ip} "${ETCD_BACKUP_CMD}")

    # --- 执行回滚 ---
    if [ -n "${K8S_LATEST_BACKUP}" ]; then
        log "找到 K8s 备份: ${K8S_LATEST_BACKUP}，正在恢复..."
        run_remote "${node_ip}" "rm -rf ${REMOTE_K8S_DIR} && mv ${K8S_LATEST_BACKUP} ${REMOTE_K8S_DIR}"
    else
        log "警告: 未在 ${hostname} 上找到 Kubernetes 配置备份。"
    fi

    if [ -n "${ETCD_LATEST_BACKUP}" ]; then
        log "找到 Etcd 备份: ${ETCD_LATEST_BACKUP}，正在恢复..."
        run_remote "${node_ip}" "rm -rf ${REMOTE_ETCD_DIR} && mv ${ETCD_LATEST_BACKUP} ${REMOTE_ETCD_DIR}"
    else
        log "警告: 未在 ${hostname} 上找到 Etcd 配置备份。"
    fi
    
    log "回滚完成，重启服务..."
    run_remote "${node_ip}" "systemctl restart kubelet etcd kube-proxy || true"
done

log "====== 回滚操作已在所有节点上触发！请手动检查集群状态。 ======"