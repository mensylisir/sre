#!/bin/bash

# --- 工作区配置 ---
# 所有临时文件和备份将存放在这个目录下
WORKSPACE_DIR="./k8s-cert-replace"

# --- 节点信息 ---
HOSTS_FILE="./hosts.info" # 包含集群所有节点 IP 的文件

# !!! 关键配置: 明确指定 etcd 和 Master 节点 IP 列表
ETCD_NODES_IP=("172.30.1.12" "172.30.1.14" "172.30.1.15")
MASTER_NODES_IP=("172.30.1.12" "172.30.1.14" "172.30.1.15")

# --- SSH 配置 ---
SSH_USER="root"
SSH_KEY="/path/to/your/ssh/private_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY}"

# --- 新证书配置 ---
CA_EXPIRY_DAYS=3650
CERT_EXPIRY_DAYS=365

# 新 CA 的 Subject 信息
K8S_CA_SUBJECT="/CN=kubernetes"
ETCD_CA_SUBJECT="/CN=etcd-ca"
FRONT_PROXY_CA_SUBJECT="/CN=front-proxy-ca"

# !!! 关键配置: APIServer 连接配置 !!!
# 用于生成所有新 kubeconfig 文件的服务器地址。
CLUSTER_APISERVER_URL="https://lb.example.com:6443"
CLUSTER_NAME="kubernetes"

# --- 远程路径配置 (根据你的环境已确认) ---
REMOTE_K8S_DIR="/etc/kubernetes"
REMOTE_ETCD_DIR="/etc/ssl/etcd/ssl"
REMOTE_KUBELET_CONF="/etc/kubernetes/kubelet.conf"