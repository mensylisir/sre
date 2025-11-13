#!/bin/bash

# --- 工作区配置 ---
WORKSPACE_DIR="./k8s-new-certs"

# --- 节点信息 ---
HOSTS_FILE="./hosts.info"

# 明确指定 etcd 和 Master 节点 IP 列表
ETCD_NODES_IP=("172.30.1.12" "172.30.1.14" "172.30.1.15")
MASTER_NODES_IP=("172.30.1.12" "172.30.1.14" "172.30.1.15")
# Worker 节点将由脚本自动计算

# --- SSH 配置 ---
SSH_USER="root"
SSH_KEY="/path/to/your/ssh/private_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY}"

# --- 证书配置 ---
CA_EXPIRY_DAYS=3650
CERT_EXPIRY_DAYS=365

# CA 的 Subject 信息
K8S_CA_SUBJECT="/CN=kubernetes"
ETCD_CA_SUBJECT="/CN=etcd-ca"
FRONT_PROXY_CA_SUBJECT="/CN=front-proxy-ca"

# ==============================================================================
# !!! SANs 配置 (动态生成) !!!
# ==============================================================================
# 以下部分留给 01-generate-all-certs.sh 脚本动态填充，你只需配置好上面的节点列表即可

# --- 额外 SANs (可选) ---
# 如果你有负载均衡器、额外的域名或特殊的 Service IP，请在这里添加
# APISERVER 额外 SANs
K8S_APISERVER_EXTRA_SANS="DNS:lb.kubesphere.local,IP:10.233.0.1"
# ETCD 额外 SANs
ETCD_EXTRA_SANS="DNS:etcd,DNS:etcd.kube-system,DNS:localhost,IP:127.0.0.1"


# --- 远程路径配置 (部署时使用) ---
REMOTE_K8S_DIR="/etc/kubernetes"
REMOTE_ETCD_DIR="/etc/ssl/etcd/ssl"