#!/bin/bash

# ==============================================================================
# 任务 3: 在所有目标节点上配置并启动 containerd
# ==============================================================================

set -e
# 加载公共函数库和环境变量
# lib.sh 中的 fetch_resources 必须已执行，以填充 ${TEMPLATE_DIR}
source ./lib.sh

# --- 1. 将 containerd 配置文件模板分发到所有目标节点 ---
log_info "开始向所有目标节点分发 containerd 配置文件..."
REMOTE_TMP_DIR="/tmp/kk-containerd-setup-$$"
pids=()
for node_info in "${ALL_NODES[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    user=$(echo "$node_info" | awk '{print $3}')
    (
        echo "  -> 正在向节点 ${ip} 分发 containerd 配置..."
        $SSH_CMD ${user}@${ip} "mkdir -p ${REMOTE_TMP_DIR}"
        
        # 使用 scp 分发从现有 Worker 复制的模板文件
        $SCP_CMD "${TEMPLATE_DIR}/containerd-config.toml" "${user}@${ip}:${REMOTE_TMP_DIR}/config.toml"
        $SCP_CMD "${TEMPLATE_DIR}/containerd.service" "${user}@${ip}:${REMOTE_TMP_DIR}/containerd.service"
        
        if [ $? -eq 0 ]; then
            echo -e "  \e[32m✔\e[0m 节点 ${ip} 配置分发成功。"
        else
            echo -e "  \e[31m✖\e[0m 节点 ${ip} 配置分发失败。"
        fi
    ) &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
log_success "所有节点 containerd 配置文件分发完毕。"


# --- 2. 在所有节点上并行执行 containerd 配置和启动脚本 ---
read -r -d '' setup_script <<EOF
set -e
REMOTE_TMP_DIR="${REMOTE_TMP_DIR}"
cd \${REMOTE_TMP_DIR}

echo "  - 正在部署 containerd 配置文件..."
mkdir -p /etc/containerd
mv ./config.toml /etc/containerd/config.toml

echo "  - 正在部署 containerd systemd 服务文件..."
mv ./containerd.service /etc/systemd/system/containerd.service

echo "  - 正在重载并启动 containerd 服务..."
systemctl daemon-reload
systemctl enable --now containerd

if ! systemctl is-active --quiet containerd; then
    echo "❌ containerd 启动失败！"
    journalctl -u containerd --no-pager -n 50
    exit 1
fi

echo "  - 清理临时文件..."
rm -rf \${REMOTE_TMP_DIR}
EOF

# 调用公共函数，在所有目标节点上执行
execute_on_all_nodes "配置并启动 containerd" "${setup_script}"