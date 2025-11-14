#!/bin/bash

# ==============================================================================
# 任务 5: 让所有目标节点加入集群 (V3 - 100% 参照 Artifact YAML)
# ==============================================================================

set -e
source ./lib.sh

log_info "开始准备让所有新节点加入集群 (基于 Artifact YAML)..."

# --- 1. 获取集群加入信息 (Token 和 Hash) ---
log_info "正在生成统一的 join token..."
JOIN_INFO=$($SSH_CMD ${EXISTING_MASTER_USER}@${EXISTING_MASTER_IP} '
    TOKEN=$(kubeadm token create);
    # 我们不再需要 HASH，因为模板里是 unsafeSkipCAVerification: true
    # HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed "s/^.* //");
    echo "TOKEN:${TOKEN}";
')
TOKEN=$(echo "$JOIN_INFO" | grep "TOKEN:" | cut -d: -f2)
if [ -z "$TOKEN" ]; then log_error "获取 Token 失败！"; exit 1; fi
log_success "Join Token 已生成。"


# --- 2. 获取 Master 加入所需的证书密钥 ---
log_info "正在为 Master 节点生成证书密钥..."
CERT_KEY=$($SSH_CMD ${EXISTING_MASTER_USER}@${EXISTING_MASTER_IP} 'kubeadm init phase upload-certs --upload-certs | tail -n 1')
if [ -z "$CERT_KEY" ]; then log_error "获取证书密钥失败！"; exit 1; fi
log_success "证书密钥已生成。"


# --- 3. 遍历所有节点，使用正确的模板生成配置并并行执行 Join ---
log_info "开始为每个节点生成配置并执行 join..."
pids=()
for node_info in "${ALL_NODES[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    role=$(echo "$node_info" | awk '{print $2}')
    user=$(echo "$node_info" | awk '{print $3}')
    
    (
        # --- 3.1 根据角色选择正确的 YAML 模板 ---
        if [ "$role" == "worker" ]; then
            # 从 Artifact 中找到一个 Worker 节点的配置作为模板 (例如 node5)
            TEMPLATE_PATH=$(find ${ARTIFACT_PATH} -path "*/node*/kubeadm-config.yaml" -exec grep -l "kind: JoinConfiguration" {} + | xargs -I {} grep -L "controlPlane" {} | head -n 1)
            if [ -z "$TEMPLATE_PATH" ]; then log_error "在 Artifact 中未找到 Worker 的 kubeadm-config.yaml 模板！"; continue; fi
            
            TEMPLATE_CONTENT=$(cat "${TEMPLATE_PATH}")
            
            # --- 3.2 动态修改 Worker 配置 ---
            modified_config=$(echo "${TEMPLATE_CONTENT}" | \
                sed "s/token: .*/token: \"${TOKEN}\"/" | \
                sed "s/tlsBootstrapToken: .*/tlsBootstrapToken: \"${TOKEN}\"/" )
            
            echo "  -> 正在以 [Worker] 身份加入节点 ${ip}..."

        elif [ "$role" == "master" ]; then
            # 从 Artifact 中找到一个新增 Master 节点的配置作为模板 (例如 node3)
            TEMPLATE_PATH=$(find ${ARTIFACT_PATH} -path "*/node*/kubeadm-config.yaml" -exec grep -l "kind: JoinConfiguration" {} + | xargs -I {} grep -l "controlPlane" {} | head -n 1)
            if [ -z "$TEMPLATE_PATH" ]; then log_error "在 Artifact 中未找到 Master 的 kubeadm-config.yaml 模板！"; continue; fi

            TEMPLATE_CONTENT=$(cat "${TEMPLATE_PATH}")
            
            # --- 3.3 动态修改 Master 配置 ---
            modified_config=$(echo "${TEMPLATE_CONTENT}" | \
                sed "s/token: .*/token: \"${TOKEN}\"/" | \
                sed "s/tlsBootstrapToken: .*/tlsBootstrapToken: \"${TOKEN}\"/" | \
                sed "s/certificateKey: .*/certificateKey: ${CERT_KEY}/" | \
                sed "s/advertiseAddress: .*/advertiseAddress: ${ip}/" )

            echo "  -> 正在以 [Master] 身份加入节点 ${ip}..."
        else
            log_error "节点 ${ip} 的角色 '${role}' 无效，跳过。"
            continue
        fi

        # --- 3.4 远程执行 join 命令 ---
        REMOTE_CONFIG_PATH="/tmp/kubeadm-join-config-${ip}.yaml"
        echo "${modified_config}" | $SSH_CMD ${user}@${ip} "cat > ${REMOTE_CONFIG_PATH}"

        command_to_run="kubeadm join --config ${REMOTE_CONFIG_PATH}"
        output=$($SSH_CMD ${user}@${ip} "sudo ${command_to_run} && sudo rm -f ${REMOTE_CONFIG_PATH}" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo -e "  \e[32m✔\e[0m 节点 ${ip} 加入集群成功。"
            if [ "$role" == "master" ]; then
                $SSH_CMD ${user}@${ip} "mkdir -p \$HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
                echo "    - 已为 Master 节点 ${ip} 配置 kubectl。"
            fi
        else
            echo -e "  \e[31m✖\e[0m 节点 ${ip} 加入集群失败。日志:"
            echo "-------------------- START LOG --------------------"
            echo "${output}"
            echo "--------------------- END LOG ---------------------"
        fi
    ) &
    pids+=($!)
done

for pid in "${pids[@]}"; do wait "$pid"; done
log_success "所有节点加入流程执行完毕。"