#!/bin/bash

# ==============================================================================
# 任务 2: 分发并安装离线二进制文件
# ==============================================================================

set -e
# 加载公共函数库和环境变量
# lib.sh 中的 fetch_resources 函数必须已执行，以填充 KUBE_BINS_PATH 等变量
source ./lib.sh

# --- 1. 将 Artifact 中的二进制文件分发到所有目标节点 ---
log_info "开始向所有目标节点分发离线二进制文件..."
REMOTE_TMP_DIR="/tmp/kk-offline-bins-$$"
pids=()
for node_info in "${ALL_NODES[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    user=$(echo "$node_info" | awk '{print $3}')
    (
        echo "  -> 正在向节点 ${ip} 分发文件..."
        # 在远程节点创建临时目录
        $SSH_CMD ${user}@${ip} "mkdir -p ${REMOTE_TMP_DIR}"
        
        # 使用 scp 分发文件
        $SCP_CMD "${KUBE_BINS_PATH}/kubelet" "${user}@${ip}:${REMOTE_TMP_DIR}/kubelet"
        $SCP_CMD "${KUBE_BINS_PATH}/kubeadm" "${user}@${ip}:${REMOTE_TMP_DIR}/kubeadm"
        $SCP_CMD "${KUBE_BINS_PATH}/kubectl" "${user}@${ip}:${REMOTE_TMP_DIR}/kubectl"
        $SCP_CMD "${CONTAINERD_PKG_PATH}" "${user}@${ip}:${REMOTE_TMP_DIR}/containerd.tar.gz"
        $SCP_CMD "${CNI_PKG_PATH}" "${user}@${ip}:${REMOTE_TMP_DIR}/cni.tgz"
        
        if [ $? -eq 0 ]; then
            echo -e "  \e[32m✔\e[0m 节点 ${ip} 文件分发成功。"
        else
            echo -e "  \e[31m✖\e[0m 节点 ${ip} 文件分发失败。"
        fi
    ) &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
log_success "所有节点文件分发完毕。"


# --- 2. 在所有节点上并行执行安装脚本 ---
read -r -d '' install_script <<EOF
set -e
REMOTE_TMP_DIR="${REMOTE_TMP_DIR}"
cd \${REMOTE_TMP_DIR}

echo "  - 正在安装 CNI 插件..."
mkdir -p /opt/cni/bin
tar -C /opt/cni/bin -xzf cni.tgz

echo "  - 正在安装 containerd..."
tar -C /usr/local -xzf containerd.tar.gz

echo "  - 正在安装 Kubernetes 二进制文件..."
install -m 755 kubelet /usr/local/bin/kubelet
install -m 755 kubeadm /usr/local/bin/kubeadm
install -m 755 kubectl /usr/local/bin/kubectl

echo "  - 清理临时文件..."
rm -rf \${REMOTE_TMP_DIR}
EOF

# 调用公共函数，在所有目标节点上执行安装
execute_on_all_nodes "安装离线二进制文件" "${install_script}"