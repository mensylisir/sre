#!/bin/bash

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] - $1"
}
# 检查命令执行状态
check_status() {
    if [ $? -ne 0 ]; then log "错误: $1"; exit 1; fi
}
# 远程操作函数
run_remote() {
    local host="$1"; shift; local cmd="$@"
    log "在 ${host} 上执行: ${cmd}"
    ssh ${SSH_OPTS} ${SSH_USER}@${host} "${cmd}"; check_status "在 ${host} 上执行命令失败！"
}
sync_to_remote() {
    local src="$1"; local dest_host="$2"; local dest_path="$3"
    log "同步 ${src} 到 ${dest_host}:${dest_path}"
    rsync -avz -e "ssh ${SSH_OPTS}" --rsync-path="mkdir -p ${dest_path%/*} && rsync" "${src}" ${SSH_USER}@${dest_host}:"${dest_path}"; check_status "同步文件到 ${dest_host} 失败！"
}
sync_from_remote() {
    local src_host="$1"; local src_path="$2"; local dest="$3"
    log "从 ${src_host}:${src_path} 拉取到 ${dest}"
    rsync -avz -e "ssh ${SSH_OPTS}" ${SSH_USER}@${src_host}:${src_path} "${dest}"; check_status "从 ${src_host} 拉取文件失败！"
}
# 确认操作
confirm_action() {
    read -p "!!! 警告: 即将为你现有的集群续期所有叶子证书。操作: [$1]。请输入 'yes' 继续: " confirm
    if [[ "$confirm" != "yes" ]]; then log "操作已取消。"; exit 0; fi
}

# 证书生成/检查函数
generate_leaf_cert() {
    local ca_cert="$1"; local ca_key="$2"; local cert_key_path="$3"; local cert_path="$4";
    local subject="$5"; local sans="$6"; local eku="$7"; local organization="$8"
    log "为 ${subject} 生成新的叶子证书"
    local csr_path="${cert_path}.csr"; local conf_path="${cert_path}.cnf"
    local cn_val=$(echo "${subject}" | sed -n 's/.*\/CN=\([^/]*\).*/\1/p')
    if [ -z "${cn_val}" ]; then log "错误: 无法从 Subject '${subject}' 中提取 CN！"; exit 1; fi
    cat > "${conf_path}" <<-EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = ${cn_val}
EOF
    if [ -n "${organization}" ]; then echo "O = ${organization}" >> "${conf_path}"; fi
    cat >> "${conf_path}" <<-EOF
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
basicConstraints = CA:FALSE
subjectAltName = @alt_names
EOF
    if [ -n "${eku}" ]; then echo "extendedKeyUsage = ${eku}" >> "${conf_path}"; fi
    echo "[alt_names]" > "${conf_path}.alt"
    if [ -n "${sans}" ]; then
        IFS=',' read -ra SAN_ARRAY <<< "$sans"; i=1
        for san in "${SAN_ARRAY[@]}"; do
            type=$(echo "${san}" | cut -d: -f1); val=$(echo "${san}" | cut -d: -f2-)
            echo "${type}.${i} = ${val}" >> "${conf_path}.alt"; i=$((i+1))
        done
    fi
    openssl req -new -newkey rsa:2048 -nodes -keyout "${cert_key_path}" -out "${csr_path}" -config "${conf_path}"
    openssl x509 -req -in "${csr_path}" -CA "${ca_cert}" -CAkey "${ca_key}" -CAcreateserial \
        -out "${cert_path}" -days "${CERT_EXPIRY_DAYS}" -extensions v3_req -extfile <(cat "${conf_path}" "${conf_path}.alt")
    check_status "签署证书 ${subject} 失败！"
    rm -f "${csr_path}" "${conf_path}" "${conf_path}.alt" "${ca_cert}.srl"
}
generate_kubeconfig() {
    local config_path="$1"; local cluster_name="$2"; local server_url="$3";
    local ca_cert_path="$4"; local user_name="$5"; local user_cert_path="$6"; local user_key_path="$7"
    log "生成 kubeconfig 文件: ${config_path}"
    ca_data=$(cat "${ca_cert_path}" | base64 | tr -d '\n')
    client_cert_data=$(cat "${user_cert_path}" | base64 | tr -d '\n')
    client_key_data=$(cat "${user_key_path}" | base64 | tr -d '\n')
    cat > "${config_path}" <<-EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${ca_data}
    server: ${server_url}
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    user: ${user_name}
  name: ${user_name}@${cluster_name}
current-context: ${user_name}@${cluster_name}
users:
- name: ${user_name}
  user:
    client-certificate-data: ${client_cert_data}
    client-key-data: ${client_key_data}
EOF
    check_status "生成 kubeconfig 文件 ${config_path} 失败！"
}
# 健康检查函数
wait_for_node_ready() {
    local node_ip="$1"
    local node_hostname=$(kubectl get node "${node_ip}" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "${node_ip}")
    log "等待节点 ${node_hostname} (${node_ip}) 恢复 Ready 状态..."
    for i in {1..30}; do
        status=$(kubectl get node "${node_ip}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$status" == "True" ]; then log "节点 ${node_hostname} (${node_ip}) 已 Ready！"; return 0; fi
        sleep 10
    done
    log "错误: 节点 ${node_hostname} (${node_ip}) 在超时时间内未能恢复 Ready 状态！"; exit 1
}

# 确认操作
confirm_action() {
    read -p "!!! 警告: 即将为你现有的集群生成并分发一套全新的 CA 和证书，这将导致全集群重启和短暂的服务中断！操作: [$1]。请输入 'yes' 继续: " confirm
    if [[ "$confirm" != "yes" ]]; then log "操作已取消。"; exit 0; fi
}