#!/bin/bash

# ==============================================================================
# 任务 6: 在所有新的 Worker 节点上部署 HAProxy 静态 Pod
# ==============================================================================

set -e
# 加载公共函数库和环境变量
# lib.sh 中的 fetch_resources 必须已执行，以填充 ${TEMPLATE_DIR}
source ./lib.sh

log_info "开始在新的 Worker 节点上部署 HAProxy..."

# --- 1. 筛选出所有角色为 'worker' 的新节点 ---
worker_nodes=()
for node_info in "${ALL_NODES[@]}"; do
    role=$(echo "$node_info" | awk '{print $2}')
    if [ "$role" == "worker" ]; then
        worker_nodes+=("$node_info")
    fi
done

if [ ${#worker_nodes[@]} -eq 0 ]; then
    log_info "在 nodes.conf 中未定义新的 Worker 节点，跳过 HAProxy 部署。"
    exit 0
fi

echo "  - 将在以下 Worker 节点上部署 HAProxy:"
for node_info in "${worker_nodes[@]}"; do
    echo "    - $(echo "$node_info" | awk '{print $1}')"
done


# --- 2. 并行分发 HAProxy 配置文件到所有新的 Worker 节点 ---
REMOTE_TMP_DIR="/tmp/kk-haproxy-setup-$$"
pids=()
for node_info in "${worker_nodes[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    user=$(echo "$node_info" | awk '{print $3}')
    (
        echo "  -> 正在向 Worker ${ip} 分发 HAProxy 配置..."
        $SSH_CMD ${user}@${ip} "mkdir -p ${REMOTE_TMP_DIR}"
        
        $SCP_CMD "${TEMPLATE_DIR}/haproxy.cfg" "${user}@${ip}:${REMOTE_TMP_DIR}/haproxy.cfg"
        $SCP_CMD "${TEMPLATE_DIR}/haproxy.yaml" "${user}@${ip}:${REMOTE_TMP_DIR}/haproxy.yaml"
        
        if [ $? -eq 0 ]; then
            echo -e "  \e[32m✔\e[0m 节点 ${ip} 配置分发成功。"
        else
            echo -e "  \e[31m✖\e[0m 节点 ${ip} 配置分发失败。"
        fi
    ) &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
log_success "所有新 Worker 节点的 HAProxy 配置文件分发完毕。"


# --- 3. 在所有新的 Worker 节点上并行执行部署 ---
read -r -d '' setup_script <<EOF
set -e
REMOTE_TMP_DIR="${REMOTE_TMP_DIR}"
cd \${REMOTE_TMP_DIR}

echo "  - 正在创建所需目录..."
mkdir -p /etc/kubekey/haproxy
mkdir -p /etc/kubernetes/manifests

echo "  - 正在部署 haproxy.cfg..."
mv ./haproxy.cfg /etc/kubekey/haproxy/haproxy.cfg

echo "  - 正在部署 haproxy.yaml 静态 Pod 定义..."
mv ./haproxy.yaml /etc/kubernetes/manifests/haproxy.yaml

echo "  - 清理临时文件..."
rm -rf \${REMOTE_TMP_DIR}

echo "  - HAProxy 已部署, kubelet 将自动拉起服务。"
EOF

# 只在 worker 节点上执行
log_info "开始在所有新 Worker 节点上执行部署脚本..."
pids=()
for node_info in "${worker_nodes[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    user=$(echo "$node_info" | awk '{print $3}')
    (
        echo "  -> 正在部署 Worker ${ip}..."
        output=$($SSH_CMD ${user}@${ip} "sudo bash -c '${setup_script}'" 2>&1)
        if [ $? -eq 0 ]; then
            echo -e "  \e[32m✔\e[0m 节点 ${ip} HAProxy 部署成功。"
        else
            echo -e "  \e[31m✖\e[0m 节点 ${ip} HAProxy 部署失败。日志:\n${output}"
        fi
    ) &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done

log_success "所有新 Worker 节点的 HAProxy 部署完毕。"