#!/bin/bash

# ==============================================================================
# 任务 4: 在所有目标节点上配置 kubelet 服务 (不启动)
# ==============================================================================

set -e
# 加载公共函数库和环境变量
source ./lib.sh

log_info "开始在所有目标节点上配置 kubelet 服务..."

# 读取 kubelet 配置文件模板的内容
KUBELET_SERVICE_TEMPLATE=$(cat "${TEMPLATE_DIR}/kubelet.service")
KUBEADM_CONF_TEMPLATE=$(cat "${TEMPLATE_DIR}/10-kubeadm.conf")

pids=()
for node_info in "${ALL_NODES[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    user=$(echo "$node_info" | awk '{print $3}')
    
    (
        echo "  -> 正在为节点 ${ip} 准备并分发 kubelet 配置..."
        
        # 1. 获取新节点的真实主机名
        hostname=$($SSH_CMD ${user}@${ip} 'hostname')
        if [ -z "$hostname" ]; then
            log_error "无法获取节点 ${ip} 的主机名！"
            continue
        fi
        
        # 2. 动态修改 10-kubeadm.conf 模板
        # 使用 sed 替换 --node-ip 和 --hostname-override 的值
        # 正则表达式匹配 "--node-ip=任意非空字符串" 并替换
        modified_kubeadm_conf=$(echo "${KUBEADM_CONF_TEMPLATE}" | \
            sed -E "s/(--node-ip=)[^ ]*/\1${ip}/" | \
            sed -E "s/(--hostname-override=)[^ ]*/\1${hostname}/")
        
        # 3. 将修改后的配置文件和 service 文件分发到远程节点
        REMOTE_TMP_DIR="/tmp/kk-kubelet-setup-$$"
        $SSH_CMD ${user}@${ip} "mkdir -p ${REMOTE_TMP_DIR}"
        
        # 使用 Heredoc 将内容写入远程文件
        echo "${KUBELET_SERVICE_TEMPLATE}" | $SSH_CMD ${user}@${ip} "cat > ${REMOTE_TMP_DIR}/kubelet.service"
        echo "${modified_kubeadm_conf}" | $SSH_CMD ${user}@${ip} "cat > ${REMOTE_TMP_DIR}/10-kubeadm.conf"

        # 4. 在远程节点上执行部署脚本
        read -r -d '' setup_script <<EOF
set -e
REMOTE_TMP_DIR="${REMOTE_TMP_DIR}"
cd \${REMOTE_TMP_DIR}

echo "  - 正在部署 kubelet systemd 服务文件..."
mv ./kubelet.service /etc/systemd/system/kubelet.service

echo "  - 正在部署 kubelet drop-in 配置文件..."
mkdir -p /etc/systemd/system/kubelet.service.d
mv ./10-kubeadm.conf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

echo "  - 正在重载并启用 kubelet 服务 (不启动)..."
systemctl daemon-reload
systemctl enable kubelet

echo "  - 清理临时文件..."
rm -rf \${REMOTE_TMP_DIR}
EOF

        output=$($SSH_CMD ${user}@${ip} "sudo bash -c '${setup_script}'" 2>&1)
        if [ $? -eq 0 ]; then
            echo -e "  \e[32m✔\e[0m 节点 ${ip} kubelet 配置成功。"
        else
            echo -e "  \e[31m✖\e[0m 节点 ${ip} kubelet 配置失败。日志:\n${output}"
        fi

    ) &
    pids+=($!)
done

for pid in "${pids[@]}"; do wait "$pid"; done
log_success "所有节点 kubelet 服务配置完毕。"