#!/bin/bash
set -e
source 00-config-sign.sh
source lib-sign.sh

log "====== 开始进行集群健康状态深度验证 ======"

cd "${WORKSPACE_DIR}" || { log "错误: 工作区目录 '${WORKSPACE_DIR}' 不存在!"; exit 1; }

# 设置 KUBECONFIG
FIRST_MASTER_IP=${MASTER_NODES_IP[0]}
if [ -z "$FIRST_MASTER_IP" ]; then log "错误: MASTER_NODES_IP 为空!"; exit 1; fi

declare -A IP_TO_HOSTNAME
if [ -f "ip_hostname_map.txt" ]; then
    while read -r ip host; do IP_TO_HOSTNAME["$ip"]="$host"; done < ip_hostname_map.txt
    FIRST_MASTER_HOSTNAME=${IP_TO_HOSTNAME[$FIRST_MASTER_IP]}
    export KUBECONFIG="${WORKSPACE_DIR}/${FIRST_MASTER_HOSTNAME}/kubernetes/admin.conf"
else
    log "警告: ip_hostname_map.txt 未找到，无法自动设置 KUBECONFIG。"
fi

# --- 1. 基础信息检查 ---
log "--- 1. 检查集群基础信息 ---"
log "--- kubectl get nodes ---"
kubectl get nodes -o wide
log "--- kubectl cluster-info ---"
kubectl cluster-info
log "--- kubectl get componentstatuses ---"
kubectl get componentstatuses

# --- 2. 核心组件 Pod 检查 ---
log "--- 2. 检查 kube-system 核心 Pods ---"
kubectl get pods -n kube-system
# 检查是否有 Pod 处于非 Running 状态
UNHEALTHY_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -n "${UNHEALTHY_PODS}" ]; then
    log "错误: kube-system 命名空间中存在不健康的 Pods: ${UNHEALTHY_PODS}"
    exit 1
fi
log "所有 kube-system Pods 均处于 Running 状态。"

# --- 3. DNS 功能验证 ---
log "--- 3. 验证集群 DNS 解析功能 ---"
TEST_POD_NAME="dns-validation-pod"
log "部署 DNS 测试 Pod: ${TEST_POD_NAME}"
kubectl run ${TEST_POD_NAME} --image=busybox:1.28 --restart=Never --command -- sleep 3600 &>/dev/null || true
# 清理 trap
trap 'log "正在清理测试 Pod..."; kubectl delete pod ${TEST_POD_NAME} --ignore-not-found &>/dev/null' EXIT

log "等待 Pod 变为 Ready..."
kubectl wait --for=condition=Ready pod/${TEST_POD_NAME} --timeout=120s
check_status "测试 Pod 未能在超时时间内变为 Ready。"

log "在 Pod 内执行 nslookup kubernetes.default..."
NSLOOKUP_RESULT=$(kubectl exec ${TEST_POD_NAME} -- nslookup kubernetes.default)
log "${NSLOOKUP_RESULT}"
if ! echo "${NSLOOKUP_RESULT}" | grep -q "Name:"; then
    log "错误: DNS 解析失败！"
    exit 1
fi
log "DNS 解析成功！"

log "清理测试 Pod..."
kubectl delete pod ${TEST_POD_NAME} --ignore-not-found &>/dev/null
trap - EXIT # 清除 trap

# --- 4. Service 和网络验证 (可选但推荐) ---
log "--- 4. 验证 Service 和 Pod 间网络 ---"
TEST_DEPLOY_NAME="nginx-validation-deploy"
TEST_SVC_NAME="nginx-validation-svc"
trap 'log "正在清理测试资源..."; kubectl delete deployment ${TEST_DEPLOY_NAME} --ignore-not-found &>/dev/null; kubectl delete service ${TEST_SVC_NAME} --ignore-not-found &>/dev/null' EXIT

log "部署 Nginx Deployment 和 Service..."
kubectl create deployment ${TEST_DEPLOY_NAME} --image=nginx:alpine --replicas=2 &>/dev/null
kubectl expose deployment ${TEST_DEPLOY_NAME} --port=80 --name=${TEST_SVC_NAME} &>/dev/null

log "等待 Deployment 可用..."
kubectl wait --for=condition=Available deployment/${TEST_DEPLOY_NAME} --timeout=120s
check_status "测试 Deployment 未能在超时时间内变为 Available。"

CLUSTER_IP=$(kubectl get service ${TEST_SVC_NAME} -o jsonpath='{.spec.clusterIP}')
log "获取到 Service ClusterIP: ${CLUSTER_IP}"

log "通过 busybox Pod 访问 Service..."
kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never -- \
  --max-time 5 curl -sS --head http://${CLUSTER_IP} | grep "200 OK"
check_status "通过 ClusterIP 访问 Service 失败！"
log "通过 ClusterIP 访问 Service 成功！"

trap - EXIT

log "====== 集群深度验证通过！ ======"