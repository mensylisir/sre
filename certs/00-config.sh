#!/bin/bash

# --- 工作区配置 ---
# 所有生成的文件将存放在堡垒机的这个目录下
WORKSPACE_DIR="/home/huoyun/k8s-ca-rotation"

# --- 节点信息 ---
# 包含所有集群节点 IP 的文件，每行一个。这是唯一需要维护的节点列表。
HOSTS_FILE="./hosts.info"

# 明确指定 etcd 和 Master 节点 IP 列表
# 脚本将自动从 hosts.info 中验证这些 IP 是否存在
ETCD_NODES=("172.30.1.12" "172.30.1.14" "172.30.1.15")
MASTER_NODES=("172.30.1.12" "172.30.1.14" "172.30.1.15")
# Worker 节点将通过从 HOSTS_FILE 排除 MASTER 节点来自动计算

# --- 远程连接配置 ---
SSH_USER="root" # 确保此用户有权访问所有相关目录并重启服务
SSH_KEY="/var/tmp/ssh_config/huoyun"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i ${SSH_KEY}"

# --- 远程路径配置 (根据您的环境已定制) ---
REMOTE_K8S_CONFIG_DIR="/etc/kubernetes"
REMOTE_ETCD_SSL_DIR="/etc/ssl/etcd/ssl"
REMOTE_KUBELET_CONFIG_DIR="/var/lib/kubelet"
REMOTE_KUBELET_CONF="${REMOTE_KUBELET_CONFIG_DIR}/kubelet.conf"
REMOTE_ETCD_ENV_FILE="/etc/etcd.env" # 根据您的信息添加

# --- 新证书配置 ---
CA_EXPIRY_DAYS=36500 # 100年
CERT_EXPIRY_DAYS=36500 # 100年

# 新 CA 的 Subject 信息
K8S_CA_SUBJECT="/CN=kubernetes"
ETCD_CA_SUBJECT="/CN=etcd-ca"
FRONT_PROXY_CA_SUBJECT="/CN=front-proxy-ca"