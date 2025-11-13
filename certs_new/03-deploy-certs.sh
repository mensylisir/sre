#!/bin/bash
set -e
source 00-config-sign.sh
source lib-sign.sh

ACTION_DESC="向所有节点分发证书和配置文件"

log "====== 开始分发所有集群证书和配置 ======"

# --- 1. 环境检查 ---
if [ ! -d "${WORKSPACE_DIR}" ]; then
    log "错误: 工作区目录 '${WORKSPACE_DIR}' 未找到！请先执行 01 和 02 脚本。"
    exit 1
fi
cd "${WORKSPACE_DIR}"

# 加载主机名映射
if [ ! -f "ip_hostname_map.txt" ]; then
    log "错误: ip_hostname_map.txt 未找到！"
    exit 1
fi
declare -A IP_TO_HOSTNAME
while read -r ip host; do IP_TO_HOSTNAME["$ip"]="$host"; done < ip_hostname_map.txt

confirm_action "${ACTION_DESC}"

# --- 2. 遍历所有节点并分发文件 ---
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log ">>> 正在处理节点: ${hostname} (${node_ip}) <<<"

    if [ ! -d "${hostname}" ]; then
        log "警告: 找不到为节点 ${hostname} 生成的证书目录，跳过此节点。"
        continue
    fi

    # --- 备份远程节点上的现有目录 (非常重要！) ---
    log "正在备份远程节点上的现有配置..."
    backup_ts=$(date +%Y%m%d-%H%M%S)
    if [[ " ${MASTER_NODES_IP[@]} " =~ " ${node_ip} " ]] || [[ " ${ETCD_NODES_IP[@]} " =~ " ${node_ip} " ]]; then
        run_remote "${node_ip}" "mv ${REMOTE_K8S_DIR} ${REMOTE_K8S_DIR}.bak.${backup_ts} || true"
        run_remote "${node_ip}" "mv ${REMOTE_ETCD_DIR} ${REMOTE_ETCD_DIR}.bak.${backup_ts} || true"
    fi

    # --- 分发 K8s 相关文件 ---
    if [ -d "${hostname}/kubernetes" ]; then
        log "分发 Kubernetes 证书和配置文件到 ${REMOTE_K8S_DIR}"
        run_remote "${node_ip}" "mkdir -p ${REMOTE_K8S_DIR}"
        sync_to_remote "${hostname}/kubernetes/" "${node_ip}" "${REMOTE_K8S_DIR}/"
        log "设置 K8s 私钥权限..."
        run_remote "${node_ip}" "find ${REMOTE_K8S_DIR} -name '*.key' -exec chmod 600 {} \\;"
    fi

    # --- 分发 Etcd 相关文件 ---
    if [ -d "${hostname}/etcd-ssl" ]; then
        log "分发 Etcd 证书到 ${REMOTE_ETCD_DIR}"
        run_remote "${node_ip}" "mkdir -p ${REMOTE_ETCD_DIR}"
        sync_to_remote "${hostname}/etcd-ssl/" "${node_ip}" "${REMOTE_ETCD_DIR}/"
        log "设置 Etcd 私钥权限..."
        run_remote "${node_ip}" "find ${REMOTE_ETCD_DIR} -name '*.key' -o -name '*.pem' -print | xargs -I {} chmod 600 {}"
    fi

    log "节点 ${hostname} 文件分发完成。"
done

log "====== 所有文件分发完毕！ ======"
log "现在你可以去各个节点上启动相应的服务了。"