#!/bin/bash

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] - $1"
}

# 远程执行命令
run_remote() {
    local host="$1"; shift; local cmd="$@"
    log "在 ${host} 上执行: ${cmd}"
    ssh ${SSH_OPTS} ${SSH_USER}@${host} "${cmd}"
    if [ $? -ne 0 ]; then log "错误: 在 ${host} 上执行命令失败！"; exit 1; fi
}

# 同步文件/目录到远程主机
sync_to_remote() {
    local src="$1"; local dest_host="$2"; local dest_path="$3"
    log "同步 ${src} 到 ${dest_host}:${dest_path}"
    rsync -avz -e "ssh ${SSH_OPTS}" --delete "${src}" ${SSH_USER}@${dest_host}:${dest_path}
    if [ $? -ne 0 ]; then log "错误: 同步文件到 ${dest_host} 失败！"; exit 1; fi
}

# 从远程主机拉取文件/目录
sync_from_remote() {
    local src_host="$1"; local src_path="$2"; local dest="$3"
    log "从 ${src_host}:${src_path} 拉取到 ${dest}"
    rsync -avz -e "ssh ${SSH_OPTS}" ${SSH_USER}@${src_host}:${src_path} "${dest}"
    if [ $? -ne 0 ]; then log "错误: 从 ${src_host} 拉取文件失败！"; exit 1; fi
}

# 确认操作
confirm_action() {
    read -p "!!! 警告: 即将对线上集群进行变更: [$1]。请输入 'yes' 继续: " confirm
    if [[ "$confirm" != "yes" ]]; then log "操作已取消。"; exit 0; fi
}

# 检查节点状态
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

# 使用 sed 更新 kubeconfig 文件中的 CA 数据
update_kubeconfig_ca() {
    local conf_file="$1"; local new_ca_base64="$2"
    log "更新文件 ${conf_file} 中的 CA 数据"
    sed -i.bak "s#\(certificate-authority-data:\).*#\1 ${new_ca_base64}#" "${conf_file}"
    if [ $? -ne 0 ]; then log "错误: 更新 ${conf_file} 失败！"; exit 1; fi
}

# 生成一个新的 CA
generate_ca() {
    local key_path="$1"; local cert_path="$2"; local subject="$3"
    log "生成新的 CA: ${subject}"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "${key_path}" -out "${cert_path}" \
        -days "${CA_EXPIRY_DAYS}" -subj "${subject}"
    if [ $? -ne 0 ]; then log "错误: 生成 CA ${subject} 失败！"; exit 1; fi
}

# 生成一个新的叶子证书
generate_leaf_cert() {
    local ca_cert="$1"; local ca_key="$2"; local cert_key_path="$3"; local cert_path="$4";
    local subject="$5"; local sans="$6"; local eku="$7"; local organization="$8"

    log "为 ${subject} 生成新的叶子证书"
    local csr_path="${cert_path}.csr"; local conf_path="${cert_path}.cnf"
    local cn_val=$(echo ${subject} | sed 's#/CN=##')

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
    IFS=',' read -ra SAN_ARRAY <<< "$sans"; i=1
    for san in "${SAN_ARRAY[@]}"; do
        type=$(echo ${san} | cut -d: -f1); val=$(echo ${san} | cut -d: -f2-)
        echo "${type}.${i} = ${val}" >> "${conf_path}.alt"; i=$((i+1))
    done

    openssl req -new -newkey rsa:2048 -nodes -keyout "${cert_key_path}" -out "${csr_path}" -config "${conf_path}"
    openssl x509 -req -in "${csr_path}" -CA "${ca_cert}" -CAkey "${ca_key}" -CAcreateserial \
        -out "${cert_path}" -days "${CERT_EXPIRY_DAYS}" -extensions v3_req -extfile <(cat "${conf_path}" "${conf_path}.alt")
    if [ $? -ne 0 ]; then log "错误: 签署证书 ${subject} 失败！"; exit 1; fi
    rm -f "${csr_path}" "${conf_path}" "${conf_path}.alt" "${ca_cert}.srl"
}