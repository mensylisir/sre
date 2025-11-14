#!/bin/bash

# ==============================================================================
# 公共函数库 (lib.sh) (V4 - 正确处理 hosts)
# ==============================================================================

# --- 全局变量 和 日志函数 ---
# 确保配置文件被加载
if [ -f "nodes.conf" ]; then
    source "nodes.conf"
else
    echo "❌ 严重错误: 配置文件 nodes.conf 未找到！"
    exit 1
fi

SSH_CMD="ssh -i ${SSH_PRIVATE_KEY_PATH} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SCP_CMD="scp -i ${SSH_PRIVATE_KEY_PATH} -o StrictHostKeyChecking=no -o ConnectTimeout=10"

log_info() {
    echo -e "\n\e[34m[INFO]\e[0m $1"
}
log_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}
log_error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# --- 核心函数 ---

# 功能: 在所有定义的目标节点上并行执行一段 bash 脚本。
execute_on_all_nodes() {
    local desc="$1"
    local script_to_execute="$2"
    log_info "开始在所有目标节点上执行: ${desc}"
    pids=()
    for node_info in "${ALL_NODES[@]}"; do
        local ip=$(echo "$node_info" | awk '{print $1}')
        local user=$(echo "$node_info" | awk '{print $3}')
        (
            echo "  -> 正在节点 ${ip} 上执行..."
            output=$($SSH_CMD ${user}@${ip} "sudo bash -c '${script_to_execute}'" 2>&1)
            if [ $? -eq 0 ]; then
                echo -e "  \e[32m✔\e[0m 节点 ${ip} 执行成功。"
            else
                echo -e "  \e[31m✖\e[0m 节点 ${ip} 执行失败。日志:"
                echo "-------------------- START LOG --------------------"
                echo "${output}"
                echo "--------------------- END LOG ---------------------"
            fi
        ) &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    log_success "所有节点已完成: ${desc}"
}


# 功能: 自动发现集群信息，定位 Artifact 资源，并复制配置文件模板。
fetch_resources() {
    log_info "正在自动发现集群信息和资源..."
    
    # --- 步骤 1: 从 Master 发现集群级信息 ---
    local master_info
    master_info=$($SSH_CMD ${EXISTING_MASTER_USER}@${EXISTING_MASTER_IP} '
        K8S_VERSION_FULL=$(kubectl get nodes -o jsonpath="{.items[0].status.nodeInfo.kubeletVersion}");
        ARCH=$(kubectl get nodes -o jsonpath="{.items[0].status.nodeInfo.architecture}");
        # 核心变更: 直接从 /etc/hosts 读取 kubekey 管理的块
        EXISTING_HOSTS_BLOCK=$(sed -n "/# kubekey hosts BEGIN/,/# kubekey hosts END/p" /etc/hosts);

        echo "K8S_VERSION_FULL:${K8S_VERSION_FULL}";
        echo "ARCH:${ARCH}";
        echo "EXISTING_HOSTS_BLOCK_START";
        echo "${EXISTING_HOSTS_BLOCK}";
        echo "EXISTING_HOSTS_BLOCK_END";
    ')
    
    if [ -z "$master_info" ]; then
        log_error "从 Master (${EXISTING_MASTER_IP}) 获取信息失败！"
        exit 1
    fi
    
    export K8S_VERSION_FULL=$(echo "$master_info" | grep "K8S_VERSION_FULL:" | cut -d: -f2)
    export K8S_VERSION=${K8S_VERSION_FULL#v}
    export ARCH=$(echo "$master_info" | grep "ARCH:" | cut -d: -f2)
    export EXISTING_HOSTS_BLOCK=$(echo "$master_info" | sed -n '/EXISTING_HOSTS_BLOCK_START/,/EXISTING_HOSTS_BLOCK_END/p' | sed '1d;$d')

    if [ -z "$EXISTING_HOSTS_BLOCK" ]; then
        log_error "从 Master 的 /etc/hosts 文件中未能找到 '# kubekey hosts' 块！"
        exit 1
    fi
    
    log_success "从 Master 发现信息完毕:"
    echo "  - Kubernetes 版本: ${K8S_VERSION_FULL}"
    echo "  - CPU 架构: ${ARCH}"
    echo "  - 已获取现有的 hosts 配置块。"

    # --- 步骤 2: 在本地 Artifact 中定位二进制文件路径 ---
    log_info "正在本地 Artifact (${ARTIFACT_PATH}) 中定位二进制文件..."
    export KUBE_BINS_PATH="${ARTIFACT_PATH}/kube/${K8S_VERSION_FULL}/${ARCH}"
    export CNI_PKG_PATH=$(find ${ARTIFACT_PATH}/cni -name "cni-plugins-linux-${ARCH}-*.tgz" | head -n 1)
    export CONTAINERD_PKG_PATH=$(find ${ARTIFACT_PATH}/containerd -name "containerd-*-linux-${ARCH}.tar.gz" | head -n 1)

    if [ ! -d "${KUBE_BINS_PATH}" ] || [ ! -f "${CNI_PKG_PATH}" ] || [ ! -f "${CONTAINERD_PKG_PATH}" ]; then
        log_error "在 Artifact 中未找到所有必需的二进制文件路径！"
        echo "  - 检查 Kubernetes 路径: ${KUBE_BINS_PATH}"
        echo "  - 检查 CNI 路径: ${CNI_PKG_PATH}"
        echo "  - 检查 Containerd 路径: ${CONTAINERD_PKG_PATH}"
        exit 1
    fi
    log_success "所有二进制文件路径定位成功。"
    
    # --- 步骤 3: 从现有 Worker 复制配置文件作为黄金模板 ---
    log_info "正在从现有 Worker (${EXISTING_WORKER_IP}) 复制配置文件模板..."
    export TEMPLATE_DIR=$(mktemp -d)
    echo "  - 模板文件将临时存放在: ${TEMPLATE_DIR}"
    
    $SCP_CMD ${EXISTING_WORKER_USER}@${EXISTING_WORKER_IP}:/etc/containerd/config.toml "${TEMPLATE_DIR}/containerd-config.toml"
    $SCP_CMD ${EXISTING_WORKER_USER}@${EXISTING_WORKER_IP}:/etc/systemd/system/kubelet.service.d/10-kubeadm.conf "${TEMPLATE_DIR}/10-kubeadm.conf"
    $SCP_CMD ${EXISTING_WORKER_USER}@${EXISTING_WORKER_IP}:/etc/systemd/system/kubelet.service "${TEMPLATE_DIR}/kubelet.service"
    $SCP_CMD ${EXISTING_WORKER_USER}@${EXISTING_WORKER_IP}:/etc/systemd/system/containerd.service "${TEMPLATE_DIR}/containerd.service"
    $SCP_CMD ${EXISTING_WORKER_USER}@${EXISTING_WORKER_IP}:/etc/kubekey/haproxy/haproxy.cfg "${TEMPLATE_DIR}/haproxy.cfg"
    $SCP_CMD ${EXISTING_WORKER_USER}@${EXISTING_WORKER_IP}:/etc/kubernetes/manifests/haproxy.yaml "${TEMPLATE_DIR}/haproxy.yaml"
    
    for f in "containerd-config.toml" "10-kubeadm.conf" "kubelet.service" "containerd.service" "haproxy.cfg" "haproxy.yaml"; do
        if [ ! -f "${TEMPLATE_DIR}/${f}" ]; then
            log_error "从 Worker 复制模板文件 ${f} 失败！"
            exit 1
        fi
    done
    
    log_success "所有配置文件模板已成功复制。"
}


# 功能: 脚本结束时清理临时文件
cleanup() {
    if [ -n "${TEMPLATE_DIR}" ] && [ -d "${TEMPLATE_DIR}" ]; then
        log_info "正在清理临时模板目录: ${TEMPLATE_DIR}"
        rm -rf "${TEMPLATE_DIR}"
    fi
}
# 使用 trap 确保脚本退出时总是执行清理
trap cleanup EXIT