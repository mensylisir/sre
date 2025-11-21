#!/bin/bash

set -e
set -o pipefail


NEW_ETCD_HOSTNAMES=("etcd1" "etcd2" "etcd3")
NEW_ETCD_IPS=("10.5.114.221" "10.5.114.222" "10.5.114.223")

MASTER_IPS=("10.5.109.1" "10.9.109.2" "10.9.109.3")

SSH_USER="root"
SSH_IDENTITY_FILE="/var/tmp/ssh_config/huoguan"
SSH_OPTIONS="-i ${SSH_IDENTITY_FILE} -o StrictHostKeyChecking=no -o ConnectTimeout=10"

CERT_SOURCE_DIR="."

REMOTE_CERT_DIR="/etc/ssl/etcd/ssl"


echo "================================================="
echo "### 开始分发证书... ###"
echo "================================================="

echo
echo "--> 正在分发证书到新的 Etcd 节点..."
for i in "${!NEW_ETCD_IPS[@]}"; do
    hostname="${NEW_ETCD_HOSTNAMES[$i]}"
    ip="${NEW_ETCD_IPS[$i]}"

    echo "    >>> 处理 Etcd 节点: ${hostname} (${ip})"
    ssh "${SSH_USER}@${ip}" "mkdir -p ${REMOTE_CERT_DIR}"

    scp ${SSH_OPTIONS} "${CERT_SOURCE_DIR}/" "${SSH_USER}@${ip}:${REMOTE_CERT_DIR}/"
    echo "    - 证书已成功复制到 ${hostname}。"
done

echo
echo "--> 正在分发证书到 Master 节点..."
for ip in "${MASTER_IPS[@]}"; do
    echo "    >>> 处理 Master 节点: ${ip}"

    echo "        - 备份远程目录 ${REMOTE_CERT_DIR}..."
    ssh ${SSH_OPTIONS} "${SSH_USER}@${ip}" "if [ -d ${REMOTE_CERT_DIR} ]; then mv ${REMOTE_CERT_DIR} ${REMOTE_CERT_DIR}_backup_$(date +%s); fi"
    
    ssh ${SSH_OPTIONS} "${SSH_USER}@${ip}" "mkdir -p ${REMOTE_CERT_DIR}"

    scp ${SSH_OPTIONS} "${CERT_SOURCE_DIR}/" "${SSH_USER}@${ip}:${REMOTE_CERT_DIR}/"
    echo "    - 证书已成功复制到 ${ip}。"
done

echo
echo "================================================="
echo "✅ 所有证书分发完毕！"
echo "================================================="