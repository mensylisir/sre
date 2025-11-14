#!/bin/bash

# ==============================================================================
# 任务 7: 更新集群中【所有】Worker 节点的 HAProxy 配置
# 独立运行，用于在 Master 节点变更后同步负载均衡。
# ==============================================================================

set -e
# 加载公共函数库和配置文件
source ./lib.sh

log_info "开始更新集群中所有 Worker 节点的 HAProxy 配置..."

# --- 1. 从 Master 获取最新的 Master 和 Worker 节点列表 ---
log_info "正在从 Master (${EXISTING_MASTER_IP}) 获取最新的集群节点列表..."
UPDATED_CLUSTER_STATE=$($SSH_CMD ${EXISTING_MASTER_USER}@${EXISTING_MASTER_IP} bash << 'EOF'
set -e
# 使用 control-plane 或 master 标签来查找 Master
MASTER_NODES=$(kubectl get nodes -l 'node-role.kubernetes.io/control-plane,node-role.kubernetes.io/master' -o custom-columns=IP:.status.addresses[?(@.type=="InternalIP")].address,NAME:.metadata.name --no-headers 2>/dev/null || \
               kubectl get nodes -l 'node-role.kubernetes.io/master' -o custom-columns=IP:.status.addresses[?(@.type=="InternalIP")].address,NAME:.metadata.name --no-headers)

# 排除 Master/control-plane 标签来查找 Worker
WORKER_NODES=$(kubectl get nodes --no-headers -l '!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' -o custom-columns=IP:.status.addresses[?(@.type=="InternalIP")].address)

echo "MASTER_NODES_START"
echo "${MASTER_NODES}"
echo "MASTER_NODES_END"
echo "WORKER_NODES_START"
echo "${WORKER_NODES}"
echo "WORKER_NODES_END"
EOF
)

UPDATED_MASTER_LIST=$(echo "${UPDATED_CLUSTER_STATE}" | sed -n '/MASTER_NODES_START/,/MASTER_NODES_END/p' | sed '1d;$d')
WORKER_NODE_LIST=$(echo "${UPDATED_CLUSTER_STATE}" | sed -n '/WORKER_NODES_START/,/WORKER_NODES_END/p' | sed '1d;$d')

if [ -z "$UPDATED_MASTER_LIST" ]; then
    log_error "获取 Master 节点列表失败！无法继续更新。"
    exit 1
elif [ -z "$WORKER_NODE_LIST" ]; then
    log_info "未发现任何 Worker 节点，无需更新 HAProxy。"
    exit 0
fi
log_success "成功获取到 $(echo -e "$UPDATED_MASTER_LIST" | wc -l) 个 Master 和 $(echo -e "$WORKER_NODE_LIST" | wc -l) 个 Worker。"


# --- 2. 根据最新的 Master 列表生成新的 haproxy.cfg 内容 ---
log_info "正在生成新的 haproxy.cfg 内容..."
HAPROXY_BACKEND_SERVERS=""
while read -r line; do
    if [ -n "$line" ]; then
        ip=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        HAPROXY_BACKEND_SERVERS+="  server ${name} ${ip}:6443 check check-ssl verify none\n"
    fi
done <<< "$UPDATED_MASTER_LIST"

# 使用从现有 Worker 复制的模板作为基础，只替换 backend 部分
HAPROXY_TEMPLATE_BASE=$(cat "${TEMPLATE_DIR}/haproxy.cfg" | sed '/backend kube_api_backend/q')
NEW_HAPROXY_CFG_CONTENT="${HAPROXY_TEMPLATE_BASE}\n${HAPROXY_BACKEND_SERVERS}"
log_success "新的 haproxy.cfg 内容已生成。"


# --- 3. 并行更新所有 Worker 节点的 HAProxy ---
log_info "将在以下所有 Worker 节点上执行更新..."
echo "${WORKER_NODE_LIST}"

# 使用 base64 编码来安全地传递配置内容
encoded_config=$(echo -e "${NEW_HAPROXY_CFG_CONTENT}" | base64 -w 0)

update_script="
echo '  - 正在更新 /etc/kubekey/haproxy/haproxy.cfg...'
echo '${encoded_config}' | base64 -d > /etc/kubekey/haproxy/haproxy.cfg

echo '  - 正在重启 HAProxy 容器...'
# 使用 crictl 查找并停止 haproxy 容器，kubelet 会自动重启它
container_id=\$(crictl ps --name haproxy -q)
if [ -n \"\$container_id\" ]; then
    crictl stop \"\$container_id\"
    echo '    - HAProxy 容器已停止，将自动重启。'
else
    echo '    - 未找到正在运行的 HAProxy 容器，无需重启。'
fi
"

pids=()
while read -r worker_ip; do
    if [ -n "$worker_ip" ]; then
        # 假设 Worker 节点的 SSH 用户是统一的，或者需要从别处获取
        user=${EXISTING_WORKER_USER}
        (
            echo "  -> 正在更新 Worker: ${worker_ip} ..."
            output=$($SSH_CMD ${user}@${worker_ip} "sudo bash -c '${update_script}'" 2>&1)
            if [ $? -eq 0 ]; then
                echo -e "  \e[32m✔\e[0m 节点 ${worker_ip} 更新成功。"
            else
                echo -e "  \e[31m✖\e[0m 节点 ${worker_ip} 更新失败。日志:\n${output}"
            fi
        ) &
        pids+=($!)
    fi
done <<< "$WORKER_NODE_LIST"
for pid in "${pids[@]}"; do wait "$pid"; done

log_success "所有 Worker 节点的 HAProxy 配置已同步至最新状态。"