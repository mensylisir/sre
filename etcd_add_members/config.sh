#!/bin/bash

# ==============================================================================
# [USER] 请在此处配置您的环境
# ==============================================================================

# --- SSH 配置 ---
SSH_USER="root"
SSH_KEY_PATH="/var/tmp/ssh_config/localhuoyun"

# --- 现有 ETCD 集群信息 ---
OLD_ETCD_HOSTNAMES=("etcd-node2" "etcd-node3" "etcd-node4")
OLD_ETCD_IPS=("172.30.1.12" "172.30.1.14" "172.30.1.15")

# --- 新增 ETCD 节点信息 ---
NEW_ETCD_HOSTNAMES=("etcd-node5" "etcd-node6")
NEW_ETCD_IPS=("172.30.1.16" "172.30.1.17")

# ---【新增】 Kubernetes Master 节点信息 (用于证书 SANs) ---
# 格式: ("master1" "master2" ...)
# 如果您的Master节点和ETCD节点有重合，也请在这里列出Master角色的主机名和IP
MASTER_HOSTNAMES=("node1" "node2" "node3") 
MASTER_IPS=("172.30.1.11" "172.30.1.12" "172.30.1.14")

# ---【新增】 其他固定的 DNS 和 IP (用于证书 SANs) ---
# 根据您的证书输出，这里包含了一些固定的 DNS 名称和可能的 VIP
# 格式: ("name1" "name2" ...)
EXTRA_SANS_DNS=("etcd" "etcd.kube-system" "etcd.kube-system.svc" "etcd.kube-system.svc.cluster.local" "lb.kubesphere.local" "localhost")
# 格式: ("ip1" "ip2" ...)
EXTRA_SANS_IPS=("127.0.0.1")


# --- ETCD 配置 ---
ETCD_CLUSTER_TOKEN="k8s_etcd"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_CERT_DIR="/etc/ssl/etcd/ssl"
ETCD_ENV_FILE="/etc/etcd.env"
ETCD_SERVICE_FILE="/etc/systemd/system/etcd.service"

# --- 证书配置 ---
CERT_ORG="Kubernetes"

# ==============================================================================
# [SYSTEM] 请勿修改以下内容
# ==============================================================================
set -o pipefail
if [[ ! -f "${SSH_KEY_PATH}" ]]; then
    echo "错误: 指定的 SSH 私钥文件不存在: ${SSH_KEY_PATH}"
    exit 1
fi
SSH_OPTIONS="-i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_CMD="ssh ${SSH_OPTIONS}"
SCP_CMD="scp ${SSH_OPTIONS}"

OLD_ENDPOINTS=""
for ip in "${OLD_ETCD_IPS[@]}"; do OLD_ENDPOINTS+="https://${ip}:2379,"; done
OLD_ENDPOINTS=${OLD_ENDPOINTS%,}