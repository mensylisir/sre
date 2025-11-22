#!/usr/bin/env bash

NEW_WORKER_IPS=(
    "10.5.67.101"
    "10.5.67.102"
)

SSH_USER="root"
SSH_IDENTITY_FILE="/var/tmp/ssh_config/huoguan"
REMOTE_KUBECONFIG_PATH="/root/.kube/config"

EXISTING_WORKER_IP="10.5.67.62"
MASTER_IP="10.5.67.176"


GLOBAL_SERVICES=(
    "registry2"
    "dockerhub"
)

BIN_PATH="/usr/bin"
SERVICE_PATH="/etc/systemd/system"
KUBEADM_CONFIG_YAML="/etc/kubernetes/kubeadm-config.yaml"
HAPROXY_MANIFEST="/etc/kubernetes/manifests/haproxy.yaml"
HAPROXY_CFG="/etc/kubekey/haproxy/haproxy.cfg"

# Validation
if [ ! -f "${SSH_IDENTITY_FILE}" ]; then
    echo -e "\033[0;31mError: SSH identity file not found at ${SSH_IDENTITY_FILE}\033[0m"
    exit 1
fi