#!/bin/bash
set -e
source 00-config-sign.sh
source lib-sign.sh

ACTION_DESC="滚动启动/重启所有 Etcd 和 Kubernetes 服务"

log "====== 开始 ${ACTION_DESC} ======"

cd "${WORKSPACE_DIR}" || { log "错误: 工作区目录 '${WORKSPACE_DIR}' 不存在!"; exit 1; }

# 加载主机名映射
if [ ! -f "ip_hostname_map.txt" ]; then log "错误: ip_hostname_map.txt 未找到！"; exit 1; fi
declare -A IP_TO_HOSTNAME
while read -r ip host; do IP_TO_HOSTNAME["$ip"]="$host"; done < ip_hostname_map.txt

# 确定用于检查的证书路径 (使用第一个 Etcd 节点的证书)
FIRST_ETCD_IP=${ETCD_NODES_IP[0]}
FIRST_ETCD_HOSTNAME=${IP_TO_HOSTNAME[$FIRST_ETCD_IP]}
ETCD_CA_CERT_PATH="cas/etcd-ca.pem"
ETCD_CLIENT_CERT_PATH="${FIRST_ETCD_HOSTNAME}/etcd-ssl/admin-${FIRST_ETCD_HOSTNAME}.pem"
ETCD_CLIENT_KEY_PATH="${FIRST_ETCD_HOSTNAME}/etcd-ssl/admin-${FIRST_ETCD_HOSTNAME}-key.pem"

# 确定用于 kubectl 的 kubeconfig 路径
FIRST_MASTER_IP=${MASTER_NODES_IP[0]}
FIRST_MASTER_HOSTNAME=${IP_TO_HOSTNAME[$FIRST_MASTER_IP]}
export KUBECONFIG="${WORKSPACE_DIR}/${FIRST_MASTER_HOSTNAME}/kubernetes/admin.conf"

confirm_action "${ACTION_DESC}"

# --- 1. 滚动重启 Etcd ---
log "--- 步骤 1: 滚动启动/重启 Etcd 服务 ---"
for node_ip in "${ETCD_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[$node_ip]}
    log ">>> 正在处理 Etcd 节点: ${hostname} (${node_ip})"
    # 假设 Etcd 是 systemd 服务。如果是静态 Pod，则此步可与 Kubelet 重启合并
    run_remote "${node_ip}" "systemctl daemon-reload && systemctl enable etcd && systemctl restart etcd"
    log "等待 30 秒让 Etcd 实例稳定..."
    sleep 30
done

log "--- Etcd 服务已全部重启，开始进行最终健康检查 ---"
check_etcd_health "${FIRST_ETCD_IP}" "${ETCD_CA_CERT_PATH}" "${ETCD_CLIENT_CERT_PATH}" "${ETCD_CLIENT_KEY_PATH}"
log "--- Etcd 集群已就绪！ ---"

# --- 2. 滚动重启所有 Kubelet ---
log "--- 步骤 2: 滚动启动/重启所有节点上的 Kubelet 和 Kube-proxy 服务 ---"
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[$node_ip]}
    log ">>> 正在处理节点: ${hostname} (${node_ip})"
    # 重启 Kubelet 会自动带起静态 Pod (APIServer, Controller-Manager, Scheduler)
    # 假设 Kube-proxy 也是 systemd 服务
    run_remote "${node_ip}" "systemctl daemon-reload && systemctl enable kubelet kube-proxy && systemctl restart kubelet kube-proxy"
    log "等待 15 秒让组件启动..."
    sleep 15
done

# --- 3. 验证集群状态 ---
log "--- 步骤 3: 等待并验证 Kubernetes 集群状态 ---"
log "等待所有节点加入集群并变为 Ready..."
for node_ip in "${ALL_NODES_IP[@]}"; do
    wait_for_node_ready "${node_ip}"
done

log "最终检查 kube-system 命名空间下的 Pod 状态..."
kubectl get pods -n kube-system -o wide

log "====== ${ACTION_DESC} 完成，集群已启动！ ======"