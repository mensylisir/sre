#!/bin/bash

# 选择一个版本，例如 v4
# wget https://github.com/mikefarah/yq/releases/download/v4.30.8/yq_linux_amd64 -O /usr/local/bin/yq
# chmod +x /usr/local/bin/yq
# 验证安装
# yq --version

# ==============================================================================
#  该脚本用于更新 kube-system 命名空间下的 kubeadm-config ConfigMap，
#  将新的 etcd 节点信息和 SANs 添加进去。
#
#  前置条件: 必须已安装 yq (https://github.com/mikefarah/yq)
# ==============================================================================

set -e
set -o pipefail

# --- 配置区域 ---

# 新 Etcd 节点的主机名列表
NEW_ETCD_HOSTNAMES=("etcd1" "etcd2" "etcd3")
# 新 Etcd 节点的 IP 列表
NEW_ETCD_IPS=("10.5.114.221" "10.5.114.222" "10.5.114.223")

# 新证书在 Master 节点上的路径
NEW_CERT_DIR="/etc/ssl/etcd/ssl"

# --- 脚本主体 ---

if ! command -v yq &> /dev/null; then
    echo "错误: yq 命令未找到。请先安装 yq。"
    echo "安装指南: https://github.com/mikefarah/yq#install"
    exit 1
fi

echo "--> 1. 获取当前的 kubeadm-config ConfigMap..."
kubectl get cm kubeadm-config -n kube-system -o yaml > kubeadm-config.original.yaml
echo "    - 当前配置已备份到 kubeadm-config.original.yaml"

# 2. 准备新的 etcd endpoints 列表
endpoints_yaml=""
for ip in "${NEW_ETCD_IPS[@]}"; do
    endpoints_yaml="${endpoints_yaml} - https://${ip}:2379"
done

echo "--> 2. 准备更新内容..."
# 提取 ClusterConfiguration 数据，这是一个 YAML 格式的字符串
yq '.data.ClusterConfiguration' kubeadm-config.original.yaml > cluster-config.yaml

# 3. 更新 ClusterConfiguration 内容
# a. 添加新的 SANs
echo "    - 添加新的 Etcd 主机名和 IP到 SANs..."
for hostname in "${NEW_ETCD_HOSTNAMES[@]}"; do
    yq e -i '.apiServer.certSANs += ["'${hostname}'"]' cluster-config.yaml
done
for ip in "${NEW_ETCD_IPS[@]}"; do
    yq e -i '.apiServer.certSANs += ["'${ip}'"]' cluster-config.yaml
done

# b. 更新 etcd external 配置
echo "    - 更新 etcd.external 配置..."
yq e -i '.etcd.external.endpoints = []' cluster-config.yaml # 清空旧的
for ip in "${NEW_ETCD_IPS[@]}"; do
    yq e -i '.etcd.external.endpoints += "https://'${ip}':2379"' cluster-config.yaml
done

yq e -i '.etcd.external.caFile = "'${NEW_CERT_DIR}'/ca.pem"' cluster-config.yaml
yq e -i '.etcd.external.certFile = "'${NEW_CERT_DIR}'/etcd-client.pem"' cluster-config.yaml
yq e -i '.etcd.external.keyFile = "'${NEW_CERT_DIR}'/etcd-client-key.pem"' cluster-config.yaml

echo "--> 3. 生成最终的 ConfigMap YAML 文件..."
# 将修改后的 ClusterConfiguration 字符串写回到主 ConfigMap 结构中
yq e '.data.ClusterConfiguration = load_str("cluster-config.yaml")' kubeadm-config.original.yaml > kubeadm-config.modified.yaml

echo "--> 4. 应用更新后的 ConfigMap到集群..."
kubectl apply -f kubeadm-config.modified.yaml

# 清理临时文件
rm cluster-config.yaml

echo
echo "================================================="
echo "✅ kubeadm-config ConfigMap 已成功更新！"
echo "此次更新主要影响未来的 'kubeadm upgrade' 和添加新控制平面节点的操作。"
echo "原始配置已备份在 kubeadm-config.original.yaml"
echo "修改后的配置保存在 kubeadm-config.modified.yaml"
echo "================================================="