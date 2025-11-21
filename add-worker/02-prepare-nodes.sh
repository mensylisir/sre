#!/usr/bin/env bash
set -e
source ./config.sh

SSH_OPTIONS="-i ${SSH_IDENTITY_FILE} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
function info { echo -e "\n${GREEN}$*${NC}"; }
function warn { echo -e "${YELLOW}$*${NC}"; }
function error { echo -e "${RED}$*${NC}"; exit 1; }

info "== [步骤 2/3] 开始为新节点批量准备二进制文件和服务 =="

FILES_TO_COPY=(
    "/usr/bin/containerd" "/usr/bin/kubelet" "/usr/local/bin/kubelet"
    "/usr/local/bin/kubeadm" "/usr/local/bin/kubectl" "/usr/bin/ctr"
    "/usr/bin/crictl" "/usr/bin/runc" "/usr/sbin/runc" "/usr/local/sbin/runc"
    "${SERVICE_PATH}/kubelet.service" "${SERVICE_PATH}/containerd.service"
    "/etc/containerd/config.toml" "/etc/crictl.yaml"
    "${KUBEADM_CONFIG_YAML}" "${HAPROXY_MANIFEST}" "${HAPROXY_CFG}"
)

warn "\n[任务 2.1] 循环为每个新节点复制文件并配置服务..."
for ip in "${NEW_WORKER_IPS[@]}"; do
    info "\n----------------- 正在准备节点: ${ip} -----------------"

    warn "  -> [${ip}] 正在创建所有目标目录..."
    ssh ${SSH_OPTIONS} ${SSH_USER}@${ip} "mkdir -p /usr/bin /usr/local/bin /usr/sbin /usr/local/sbin ${SERVICE_PATH} /etc/containerd /etc/kubernetes/manifests /etc/haproxy /etc/kubekey/haproxy"

    warn "  -> [${ip}] 正在从 ${EXISTING_WORKER_IP} 复制文件..."
    for file_path in "${FILES_TO_COPY[@]}"; do
        dir=$(dirname "${file_path}")
        
        if ssh ${SSH_OPTIONS} ${SSH_USER}@${EXISTING_WORKER_IP} "test -e ${file_path}"; then
            echo "     -> 正在复制 ${file_path}..."
            scp ${SSH_OPTIONS} ${SSH_USER}@${EXISTING_WORKER_IP}:${file_path} ${SSH_USER}@${ip}:${dir}/
        else
            warn "     -> 警告: 在参考节点上未找到 ${file_path}，已跳过。"
        fi
    done

    warn "  -> [${ip}] 正在远程执行权限设置和服务配置..."
    ssh ${SSH_OPTIONS} ${SSH_USER}@${ip} 'bash -s' <<'EOF'
set -e
echo "  -> [self] 设置文件执行权限..."
find /usr/bin /usr/local/bin /usr/sbin /usr/local/sbin -type f \
    \( -name "containerd" -o -name "kubelet" -o -name "kubeadm" -o -name "kubectl" -o -name "ctr" -o -name "crictl" -o -name "runc" \) \
    -exec chmod +x {} +

echo "  -> [self] 重载服务并启用 containerd 和 kubelet..."
systemctl daemon-reload
systemctl enable --now containerd
systemctl enable kubelet
EOF
    info "  -> [${ip}] 文件和基础服务准备完成。"
done

info "\n== 所有新节点的文件准备工作已完成！接下来请执行 03-join-cluster.sh。 =="