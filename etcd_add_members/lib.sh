#!/bin/bash

# ==============================================================================
# 公共函数库 (lib.sh) - V5
# 优化了证书生成逻辑以匹配现有结构
# ==============================================================================

# --- 日志和颜色 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_step() { echo -e "\n${GREEN}====> 步骤 ${STEP_COUNT}: ${1}...${NC}"; ((STEP_COUNT++)); }
log_info() { echo -e "${NC}${1}${NC}"; }
log_warn() { echo -e "${YELLOW}${1}${NC}"; }
log_error() { echo -e "${RED}${1}${NC}"; exit 1; }

# --- 远程操作 ---
remote_exec() { ${SSH_CMD} "${SSH_USER}@${1}" "${2}"; }
remote_upload() { ${SCP_CMD} "${1}" "${SSH_USER}@${2}:${3}"; }
remote_download() { ${SCP_CMD} "${SSH_USER}@${1}:${2}" "${3}"; }

# --- 文件操作 ---
ensure_remote_dir() { remote_exec "$1" "mkdir -p ${2}"; }

upload_file_if_changed() {
    local local_md5=$(md5sum "${1}" | awk '{print $1}')
    local remote_md5=$(remote_exec "$2" "md5sum ${3} 2>/dev/null | awk '{print \$1}'" || echo "notfound")
    if [[ "$local_md5" != "$remote_md5" ]]; then
        log_info "上传或更新文件: $(basename ${1}) 到 ${2}"
        remote_upload "$1" "$2" "$3"
        return 0
    else
        log_info "文件 $(basename ${1}) 在 ${2} 上已是最新，跳过上传。"
        return 1
    fi
}

# --- 证书生成 (已更新) ---
generate_node_certs() {
    local name="$1"
    local local_cert_dir="$2"
    local tmp_dir="$3"
    
    # 检查所有三种证书是否都已生成
    if [[ -f "${local_cert_dir}/member-${name}.pem" && -f "${local_cert_dir}/admin-${name}.pem" && -f "${local_cert_dir}/node-${name}.pem" ]]; then
         log_info "节点 ${name} 的所有证书已在本地生成，跳过。"
         return
    fi
    log_info "为节点 ${name} 生成 member, admin, 和 node 证书..."

    # 创建通用的 openssl 配置文件模板
    cat > "${tmp_dir}/openssl-${name}.cnf.template" <<-EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = __CN_PLACEHOLDER__
O = ${CERT_ORG}
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
${SANS_CONFIG}
EOF

    # 为每种证书类型生成证书
    for cert_type in member admin node; do
        local cn_prefix="etcd-${cert_type}"
        # 特殊处理 node 证书的 CN 格式
        if [[ "$cert_type" == "node" ]]; then
            cn_prefix="etcd-node"
        fi
        
        local cert_cn="${cn_prefix}-${name}"
        local cert_file_base="${cert_type}-${name}"
        
        local cnf_file="${tmp_dir}/openssl-${cert_file_base}.cnf"
        cp "${tmp_dir}/openssl-${name}.cnf.template" "$cnf_file"
        sed -i "s/__CN_PLACEHOLDER__/${cert_cn}/" "$cnf_file"

        openssl genrsa -out "${local_cert_dir}/${cert_file_base}-key.pem" 2048 &> /dev/null
        openssl req -new -key "${local_cert_dir}/${cert_file_base}-key.pem" -out "${tmp_dir}/${cert_file_base}.csr" -config "$cnf_file"
        openssl x509 -req -in "${tmp_dir}/${cert_file_base}.csr" -CA "${local_cert_dir}/ca.pem" -CAkey "${local_cert_dir}/ca-key.pem" -CAcreateserial -out "${local_cert_dir}/${cert_file_base}.pem" -days 3650 -extensions v3_req -extfile "$cnf_file"
    done
}

# --- ETCD 服务操作 ---
is_etcd_active() { remote_exec "$1" "systemctl is-active etcd" &> /dev/null; }

restart_etcd_service() {
    log_info "重启 ${1} 上的 etcd 服务..."
    remote_exec "$1" "systemctl restart etcd"
    sleep 5
    if ! is_etcd_active "$1"; then
        log_error "错误: 重启节点 ${1} 上的 ETCD 服务失败！"
        remote_exec "$1" "journalctl -u etcd -n 50 --no-pager"
    fi
    log_info "节点 ${1} 服务重启成功。"
}

start_etcd_service() {
    log_info "在 ${1} 上配置并启动 ETCD 服务..."
    remote_exec "$1" "systemctl daemon-reload && systemctl enable etcd && systemctl start etcd"
    sleep 5
    if ! is_etcd_active "$1"; then
        log_error "错误: 节点 ${1} 上的 ETCD 服务启动失败！"
        remote_exec "$1" "journalctl -u etcd -n 50 --no-pager"
    fi
}