#!/bin/bash
set -e
source 00-config-sign.sh
source lib-sign.sh

log "====== 开始生成所有 kubeconfig 文件 ======"

# --- 1. 环境检查 ---
if [ ! -d "${WORKSPACE_DIR}" ]; then
    log "错误: 工作区目录 '${WORKSPACE_DIR}' 未找到！请先执行 01-generate-all-certs.sh。"
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

# --- 2. 为所有节点生成 kubelet.conf ---
log "--- 步骤 2: 为所有节点生成 kubelet.conf ---"
for node_ip in "${ALL_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log "为节点 ${hostname} 生成 kubelet.conf..."
    
    generate_kubeconfig \
        "${hostname}/kubernetes/kubelet.conf" \
        "${CLUSTER_NAME}" \
        "${CLUSTER_APISERVER_URL}" \
        "cas/ca.crt" \
        "system:node:${hostname}" \
        "${hostname}/kubernetes/kubelet.crt" \
        "${hostname}/kubernetes/kubelet.key"
done

# --- 3. 为 Master 节点生成其他 .conf 文件 ---
log "--- 步骤 3: 为 Master 节点生成 admin.conf, controller-manager.conf, scheduler.conf ---"
for node_ip in "${MASTER_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    
    log "为 Master 节点 ${hostname} 生成 admin.conf..."
    generate_kubeconfig \
        "${hostname}/kubernetes/admin.conf" \
        "${CLUSTER_NAME}" \
        "${CLUSTER_APISERVER_URL}" \
        "cas/ca.crt" \
        "kubernetes-admin" \
        "${hostname}/kubernetes/admin.crt" \
        "${hostname}/kubernetes/admin.key"

    log "为 Master 节点 ${hostname} 生成 controller-manager.conf..."
    generate_kubeconfig \
        "${hostname}/kubernetes/controller-manager.conf" \
        "${CLUSTER_NAME}" \
        "${CLUSTER_APISERVER_URL}" \
        "cas/ca.crt" \
        "system:kube-controller-manager" \
        "${hostname}/kubernetes/controller-manager.crt" \
        "${hostname}/kubernetes/controller-manager.key"
        
    log "为 Master 节点 ${hostname} 生成 scheduler.conf..."
    generate_kubeconfig \
        "${hostname}/kubernetes/scheduler.conf" \
        "${CLUSTER_NAME}" \
        "${CLUSTER_APISERVER_URL}" \
        "cas/ca.crt" \
        "system:kube-scheduler" \
        "${hostname}/kubernetes/scheduler.crt" \
        "${hostname}/kubernetes/scheduler.key"

    log "为 Master 节点 ${hostname} 生成 kube-proxy.conf..."
    generate_kubeconfig \
        "${hostname}/kubernetes/kube-proxy.conf" \
        "${CLUSTER_NAME}" \
        "${CLUSTER_APISERVER_URL}" \
        "cas/ca.crt" \
        "system:kube-proxy" \
        "${hostname}/kubernetes/kube-proxy.crt" \
        "${hostname}/kubernetes/kube-proxy.key"
        
done

log "====== 所有 kubeconfig 文件生成完毕！ ======"