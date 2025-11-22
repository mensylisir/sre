#!/usr/bin/env bash
set -e
source ./config.sh

SSH_OPTIONS="-i ${SSH_IDENTITY_FILE} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
function info { echo -e "${GREEN}$*${NC}"; }
function warn { echo -e "${YELLOW}$*${NC}"; }
function error { echo -e "${RED}$*${NC}"; exit 1; }

info "== [步骤 3/3] 开始将所有新节点加入集群 =="

warn "\n[任务 3.1] 获取一个可供所有节点使用的 Join Token..."
NEW_JOIN_TOKEN=$(ssh ${SSH_OPTIONS} ${SSH_USER}@${MASTER_IP} "kubeadm token create")
[ -z "$NEW_JOIN_TOKEN" ] && error "错误：无法生成 kubeadm token。"
info "  -> 成功获取 Token: ${NEW_JOIN_TOKEN}"

warn "\n[任务 3.2] 循环处理每个新节点，执行加入和HA切换..."
for ip in "${NEW_WORKER_IPS[@]}"; do
    info "\n----------------- 正在加入节点: ${ip} -----------------"
    ssh ${SSH_OPTIONS} ${SSH_USER}@${ip} 'bash -s' <<EOF
set -e
# 从主脚本继承变量
MASTER_IP="${MASTER_IP}"
NEW_JOIN_TOKEN="${NEW_JOIN_TOKEN}"
KUBEADM_CONFIG_YAML="${KUBEADM_CONFIG_YAML}"

echo "  -> [${ip}] 更新 kubeadm join 配置文件..."
sed -i "s/token: .*/token: \${NEW_JOIN_TOKEN}/" \${KUBEADM_CONFIG_YAML}
sed -i "s/tlsBootstrapToken: .*/tlsBootstrapToken: \${NEW_JOIN_TOKEN}/" \${KUBEADM_CONFIG_YAML}
# 移除可能存在的固定节点名称，强制使用当前主机名
sed -i "/name:/d" \${KUBEADM_CONFIG_YAML}

echo "  -> [${ip}] 临时配置 hosts 用于引导..."
# 为保证幂等性，先删除可能存在的旧条目
sed -i '/lb.cars.local/d' /etc/hosts
echo "\${MASTER_IP}  lb.cars.local" >> /etc/hosts

echo "  -> [${ip}] 执行 kubeadm join... (这可能需要几分钟)"
kubeadm join --config \${KUBEADM_CONFIG_YAML}
echo "  -> [${ip}] 节点成功加入集群！"

echo "  -> [${ip}] 切换到本地 HAProxy 模式..."
echo "     -> 等待本地 HAProxy Pod 启动..."
timeout=180
while ! crictl ps | grep -q haproxy; do
  sleep 5; timeout=\$((timeout - 5))
  if [ \$timeout -le 0 ]; then
    echo "错误：等待 HAProxy Pod 启动超时！" >&2; exit 1
  fi
done
echo "     -> 本地 HAProxy Pod 已成功运行。"

echo "     -> 修正 /etc/hosts 指向 127.0.0.1..."
sed -i '/lb.cars.local/d' /etc/hosts
echo '127.0.0.1  lb.cars.local' >> /etc/hosts

echo "     -> 重启 Kubelet..."
systemctl restart kubelet
EOF
    info "  -> [${ip}] 节点完全配置并加入集群成功。"
done

info "\n=========================================================="
info "==  所有新节点已成功添加到集群！                     =="
info "==  请在 Master 节点执行 'kubectl get nodes -o wide' 进行验证。 =="
info "=========================================================="
