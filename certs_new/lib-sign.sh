#!/bin/bash

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] - $1"
}

# 检查命令执行状态
check_status() {
    if [ $? -ne 0 ]; then
        log "错误: $1"
        exit 1
    fi
}

# 生成一个新的 CA
generate_ca() {
    local key_path="$1"
    local cert_path="$2"
    local subject="$3"
    
    log "生成新的 CA: ${subject}"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "${key_path}" -out "${cert_path}" \
        -days "${CA_EXPIRY_DAYS}" -subj "${subject}"
    check_status "生成 CA ${subject} 失败！"
}

# 生成一个新的叶子证书
generate_leaf_cert() {
    local ca_cert="$1"
    local ca_key="$2"
    local cert_key_path="$3"
    local cert_path="$4"
    local subject="$5"
    local sans="$6"
    local eku="$7"
    local organization="$8"

    log "为 ${subject} 生成新的叶子证书"
    local csr_path="${cert_path}.csr"
    local conf_path="${cert_path}.cnf"
    
    # 从 Subject 中提取 CN
    local cn_val=$(echo "${subject}" | sed -n 's/.*\/CN=\([^/]*\).*/\1/p')
    if [ -z "${cn_val}" ]; then
        log "错误: 无法从 Subject '${subject}' 中提取 CN！"
        exit 1
    fi

    # 创建 OpenSSL 配置文件
    cat > "${conf_path}" <<-EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = ${cn_val}
EOF
    if [ -n "${organization}" ]; then
        echo "O = ${organization}" >> "${conf_path}"
    fi

    cat >> "${conf_path}" <<-EOF
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
basicConstraints = CA:FALSE
subjectAltName = @alt_names
EOF
    if [ -n "${eku}" ]; then
        echo "extendedKeyUsage = ${eku}" >> "${conf_path}"
    fi
    
    # 动态生成 SANs 部分
    echo "[alt_names]" > "${conf_path}.alt"
    if [ -n "${sans}" ]; then
        IFS=',' read -ra SAN_ARRAY <<< "$sans"
        local i=1
        for san in "${SAN_ARRAY[@]}"; do
            local type=$(echo "${san}" | cut -d: -f1)
            local val=$(echo "${san}" | cut -d: -f2-)
            echo "${type}.${i} = ${val}" >> "${conf_path}.alt"
            i=$((i+1))
        done
    fi

    # 生成 CSR 和证书
    openssl req -new -newkey rsa:2048 -nodes -keyout "${cert_key_path}" -out "${csr_path}" -config "${conf_path}"
    check_status "为 ${subject} 生成 CSR 失败！"
    
    openssl x509 -req -in "${csr_path}" -CA "${ca_cert}" -CAkey "${ca_key}" -CAcreateserial \
        -out "${cert_path}" -days "${CERT_EXPIRY_DAYS}" -extensions v3_req -extfile <(cat "${conf_path}" "${conf_path}.alt")
    check_status "签署证书 ${subject} 失败！"

    # 清理临时文件
    rm -f "${csr_path}" "${conf_path}" "${conf_path}.alt" "${ca_cert}.srl"
}


generate_kubeconfig() {
    local config_path="$1"
    local cluster_name="$2"
    local server_url="$3"
    local ca_cert_path="$4"
    local user_name="$5"
    local user_cert_path="$6"
    local user_key_path="$7"

    log "生成 kubeconfig 文件: ${config_path}"

    # 获取 CA 证书的 Base64 编码
    local ca_data=$(cat "${ca_cert_path}" | base64 | tr -d '\n')
    
    # 获取用户证书和密钥的 Base64 编码
    local client_cert_data=$(cat "${user_cert_path}" | base64 | tr -d '\n')
    local client_key_data=$(cat "${user_key_path}" | base64 | tr -d '\n')

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

run_remote() {
    local host="$1"; shift; local cmd="$@"
    log "在 ${host} 上执行: ${cmd}"
    ssh ${SSH_OPTS} ${SSH_USER}@${host} "${cmd}"
    check_status "在 ${host} 上执行命令失败！"
}

# 同步文件/目录到远程主机
sync_to_remote() {
    local src="$1"; local dest_host="$2"; local dest_path="$3"
    log "同步 ${src} 到 ${dest_host}:${dest_path}"
    rsync -avz -e "ssh ${SSH_OPTS}" --rsync-path="mkdir -p ${dest_path%/*} && rsync" "${src}" ${SSH_USER}@${dest_host}:"${dest_path}"
    check_status "同步文件到 ${dest_host} 失败！"
}

# 确认操作
confirm_action() {
    read -p "!!! 警告: 即将向线上节点分发全新证书，这将覆盖现有文件！操作: [$1]。请输入 'yes' 继续: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log "操作已取消。"
        exit 0
    fi
}

wait_for_node_ready() {
    local node_ip="$1"
    # 尝试从 kubectl 获取主机名，如果失败则直接使用 IP
    local node_hostname=$(kubectl get node "${node_ip}" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "${node_ip}")
    log "等待节点 ${node_hostname} (${node_ip}) 恢复 Ready 状态..."
    # 增加超时时间，例如 5 分钟 (30 * 10s)
    for i in {1..30}; do
        # 错误输出重定向到 /dev/null，避免在节点还未加入时报错
        status=$(kubectl get node "${node_ip}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$status" == "True" ]; then
            log "节点 ${node_hostname} (${node_ip}) 已 Ready！"
            return 0
        fi
        sleep 10
    done
    log "错误: 节点 ${node_hostname} (${node_ip}) 在超时时间内未能恢复 Ready 状态！"
    exit 1
}

# 检查 Etcd 集群健康状态
check_etcd_health() {
    local target_host="$1"
    local etcd_ca_path="$2"
    local etcd_cert_path="$3"
    local etcd_key_path="$4"
    
    local etcd_endpoints=""
    for ip in "${ETCD_NODES_IP[@]}"; do
        etcd_endpoints+="${ip}:${ETCD_CLIENT_PORT},"
    done
    etcd_endpoints=${etcd_endpoints%,} # 移除末尾的逗号

    local remote_tmp_dir="/tmp/etcd_health_check_$$"
    # 设置 trap 确保临时文件一定被清理
    trap 'log "执行清理操作: rm -rf ${remote_tmp_dir} on ${target_host}"; run_remote "${target_host}" "rm -rf ${remote_tmp_dir}"; trap - RETURN EXIT INT TERM' RETURN EXIT INT TERM

    run_remote "${target_host}" "mkdir -p ${remote_tmp_dir}"
    sync_to_remote "${etcd_ca_path}" "${target_host}" "${remote_tmp_dir}/ca.pem"
    sync_to_remote "${etcd_cert_path}" "${target_host}" "${remote_tmp_dir}/cert.pem"
    sync_to_remote "${etcd_key_path}" "${target_host}" "${remote_tmp_dir}/key.pem"

    log "在 ${target_host} 上检查 Etcd 集群 (${etcd_endpoints}) 的健康状态..."

    local etcdctl_cmd="ETCDCTL_API=3 ${REMOTE_ETCDCTL_PATH:-etcdctl} \
        --endpoints=${etcd_endpoints} \
        --cacert=${remote_tmp_dir}/ca.pem \
        --cert=${remote_tmp_dir}/cert.pem \
        --key=${remote_tmp_dir}/key.pem \
        endpoint health --cluster"

    local health_output
    health_output=$(ssh ${SSH_OPTS} ${SSH_USER}@${target_host} "${etcdctl_cmd}" 2>&1)
    local exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        log "错误: etcdctl 命令执行失败！"
        log "输出: ${health_output}"
        exit 1
    fi

    if echo "${health_output}" | grep -q "is unhealthy"; then
        log "错误: Etcd 集群中有不健康的成员！"
        log "输出: ${health_output}"
        exit 1
    fi
    log "Etcd 集群健康检查通过！所有成员均健康。"
}