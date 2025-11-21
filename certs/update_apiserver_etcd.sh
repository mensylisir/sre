#!/bin/bash

# ==============================================================================
#  该脚本用于更新所有 Master 节点上的 /etc/kubernetes/manifests/kube-apiserver.yaml
#  文件，将其中的 etcd 配置指向新的 etcd 集群和证书。
#
#  警告：此操作会导致 kube-apiserver Pod 滚动重启，请在维护窗口执行！
# ==============================================================================

set -e
set -o pipefail

# --- 配置区域 ---

# Master 节点的 IP 列表
MASTER_IPS=("10.5.109.1" "10.9.109.2" "10.9.109.3")

# 新 Etcd 节点的 IP 列表
NEW_ETCD_IPS=("10.5.114.221" "10.5.114.222" "10.5.114.223")

# 用哪个用户 SSH 登录到 Master 节点
SSH_USER="root"

# 新证书在 Master 节点上的路径
NEW_CERT_DIR="/etc/ssl/etcd/ssl"

# kube-apiserver manifest 文件的路径
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"

# --- 脚本主体 ---

# 1. 根据新 Etcd IP 列表，构建 --etcd-servers 参数字符串
etcd_servers_string=""
for ip in "${NEW_ETCD_IPS[@]}"; do
    if [ -z "$etcd_servers_string" ]; then
        etcd_servers_string="https://"${ip}":2379"
    else
        etcd_servers_string="${etcd_servers_string},https://"${ip}":2379"
    fi
done
echo "将要更新的 etcd-servers 列表为: ${etcd_servers_string}"
echo

# 2. 遍历所有 Master 节点并执行更新
for ip in "${MASTER_IPS[@]}"; do
    echo ">>> 正在更新 Master 节点: ${ip}"

    # 定义远程执行的命令
    # 使用 'EOF' 可以方便地在远程执行多行命令
    ssh "${SSH_USER}@${ip}" "bash -s" <<EOF
set -e
echo "    - 备份 ${APISERVER_MANIFEST}..."
cp ${APISERVER_MANIFEST} ${APISERVER_MANIFEST}.bak_$(date +%s)

echo "    - 正在更新 etcd 配置..."
sed -i \
    -e 's|--etcd-servers=.*|--etcd-servers=${etcd_servers_string}|' \
    -e 's|--etcd-cafile=.*|--etcd-cafile=${NEW_CERT_DIR}/ca.pem|' \
    -e 's|--etcd-certfile=.*|--etcd-certfile=${NEW_CERT_DIR}/etcd-client.pem|' \
    -e 's|--etcd-keyfile=.*|--etcd-keyfile=${NEW_CERT_DIR}/etcd-client-key.pem|' \
    ${APISERVER_MANIFEST}

echo "    - 更新完成。Kubelet 将会自动重启 kube-apiserver Pod。"
EOF

    echo ">>> 节点 ${ip} 处理完毕。"
    echo
done

echo "================================================="
echo "✅ 所有 Master 节点的 kube-apiserver.yaml 已更新。"
echo "请稍等片刻，然后通过 'kubectl get pods -n kube-system' 检查 kube-apiserver Pod 是否已重启成功。"
echo "并通过 'kubectl get --raw=/readyz' 检查集群健康状态。"
echo "================================================="