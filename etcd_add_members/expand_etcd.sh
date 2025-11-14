#!/bin/bash

# ==============================================================================
# ETCD 集群安全扩容主脚本 (V6 - 包含 Master 节点 SANs)
# ==============================================================================
set -e
BASE_DIR=$(dirname "$0")
cd "$BASE_DIR"

source ./config.sh
source ./lib.sh

# --- 全局变量 ---
STEP_COUNT=1
TMP_DIR=$(mktemp -d)
LOCAL_BIN_DIR="${TMP_DIR}/bin"
LOCAL_CERT_DIR="${TMP_DIR}/certs"
mkdir -p "$LOCAL_BIN_DIR" "$LOCAL_CERT_DIR"

# --- 清理函数 ---
cleanup() { log_warn "执行清理操作，删除临时目录 ${TMP_DIR}..."; rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- 业务逻辑函数 ---

task_prepare_workspace() {
    log_step "准备本地工作区"
    local source_host="${OLD_ETCD_HOSTNAMES[0]}"
    if [[ ! -f "${LOCAL_CERT_DIR}/ca.pem" || ! -f "${LOCAL_CERT_DIR}/ca-key.pem" ]]; then
        log_info "从 ${source_host} 下载 CA 证书和私钥..."
        if ! remote_download "$source_host" "${ETCD_CERT_DIR}/ca.pem" "${LOCAL_CERT_DIR}/" || \
           ! remote_download "$source_host" "${ETCD_CERT_DIR}/ca-key.pem" "${LOCAL_CERT_DIR}/"; then
            log_error "无法下载 CA 文件。请确认 ${ETCD_CERT_DIR}/ca-key.pem 文件在源节点上存在且可读。"
        fi
    fi
    remote_download "$source_host" "/usr/local/bin/etcd" "${LOCAL_BIN_DIR}/"
    remote_download "$source_host" "/usr/local/bin/etcdctl" "${LOCAL_BIN_DIR}/"
    remote_download "$source_host" "$ETCD_ENV_FILE" "${TMP_DIR}/etcd.env.template"
    remote_download "$source_host" "$ETCD_SERVICE_FILE" "${TMP_DIR}/etcd.service.template"
    log_info "本地工作区准备就绪。"
}

# [已更新]
task_generate_all_certs() {
    log_step "生成所有需要的证书 (包含 Master 和额外 SANs)"
    
    # 合并所有 Hostnames 和 IPs，并去重
    ALL_HOSTNAMES=($(echo "${OLD_ETCD_HOSTNAMES[@]}" "${NEW_ETCD_HOSTNAMES[@]}" "${MASTER_HOSTNAMES[@]}" "${EXTRA_SANS_DNS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    ALL_IPS=($(echo "${OLD_ETCD_IPS[@]}" "${NEW_ETCD_IPS[@]}" "${MASTER_IPS[@]}" "${EXTRA_SANS_IPS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    # 准备 SANS 配置
    SANS_CONFIG="[alt_names]\n"
    DNS_COUNT=1 && IP_COUNT=1
    for name in "${ALL_HOSTNAMES[@]}"; do SANS_CONFIG+="DNS.${DNS_COUNT} = ${name}\n"; ((DNS_COUNT++)); done
    for ip in "${ALL_IPS[@]}"; do SANS_CONFIG+="IP.${IP_COUNT} = ${ip}\n"; ((IP_COUNT++)); done

    # 为所有节点（新旧）生成证书
    NODES_TO_CERT=("${NEW_ETCD_HOSTNAMES[@]}" "${OLD_ETCD_HOSTNAMES[@]}")
    for name in "${NODES_TO_CERT[@]}"; do
        generate_node_certs "$name" "$LOCAL_CERT_DIR" "$TMP_DIR"
    done
    log_info "所有必需的证书已生成。"
}

task_register_new_members() {
    log_step "注册新成员到集群"
    local source_host="${OLD_ETCD_HOSTNAMES[0]}"
    for i in "${!NEW_ETCD_HOSTNAMES[@]}"; do
        local name="${NEW_ETCD_HOSTNAMES[$i]}"
        local ip="${NEW_ETCD_IPS[$i]}"
        local list_cmd="ETCDCTL_API=3 etcdctl --endpoints=${OLD_ENDPOINTS} --cacert=${ETCD_CERT_DIR}/ca.pem --cert=${ETCD_CERT_DIR}/admin-${source_host}.pem --key=${ETCD_CERT_DIR}/admin-${source_host}-key.pem member list"
        if remote_exec "$source_host" "$list_cmd" | grep -q "peerURLs=https://{ip}:2380"; then
            log_info "成员 ${name} (https://{ip}:2380) 已注册，跳过。"
        else
            log_info "注册新成员 ${name}..."
            local add_cmd="ETCDCTL_API=3 etcdctl --endpoints=${OLD_ENDPOINTS} --cacert=${ETCD_CERT_DIR}/ca.pem --cert=${ETCD_CERT_DIR}/admin-${source_host}.pem --key=${ETCD_CERT_DIR}/admin-${source_host}-key.pem member add ${name} --peer-urls=https://{ip}:2380"
            if ! remote_exec "$source_host" "$add_cmd" | grep -q "Member added to cluster"; then log_error "注册成员 ${name} 失败！"; fi
            log_info "成员 ${name} 注册成功。"
        fi
    done
}

task_deploy_new_nodes() {
    log_step "部署新 ETCD 节点"
    for i in "${!NEW_ETCD_HOSTNAMES[@]}"; do
        local name="${NEW_ETCD_HOSTNAMES[$i]}"
        local ip="${NEW_ETCD_IPS[$i]}"
        log_info "--- 开始部署节点 ${name} ---"
        ensure_remote_dir "$name" "/usr/local/bin ${ETCD_DATA_DIR} ${ETCD_CERT_DIR}"

        upload_file_if_changed "${LOCAL_BIN_DIR}/etcd" "$name" "/usr/local/bin/etcd" && remote_exec "$name" "chmod +x /usr/local/bin/etcd"
        upload_file_if_changed "${LOCAL_BIN_DIR}/etcdctl" "$name" "/usr/local/bin/etcdctl" && remote_exec "$name" "chmod +x /usr/local/bin/etcdctl"
        
        upload_file_if_changed "${LOCAL_CERT_DIR}/ca.pem" "$name" "${ETCD_CERT_DIR}/ca.pem"
        for cert_type in member admin node; do
             upload_file_if_changed "${LOCAL_CERT_DIR}/${cert_type}-${name}.pem" "$name" "${ETCD_CERT_DIR}/${cert_type}-${name}.pem"
             upload_file_if_changed "${LOCAL_CERT_DIR}/${cert_type}-${name}-key.pem" "$name" "${ETCD_CERT_DIR}/${cert_type}-${name}-key.pem"
        done

        if is_etcd_active "$name"; then
            log_info "ETCD 服务已在 ${name} 上运行，跳过配置和启动。"
        else
            local new_env_file="${TMP_DIR}/etcd.env.${name}"; cp "${TMP_DIR}/etcd.env.template" "$new_env_file"
            ALL_HOSTNAMES_CFG=("${OLD_ETCD_HOSTNAMES[@]}" "${NEW_ETCD_HOSTNAMES[@]}"); ALL_IPS_CFG=("${OLD_ETCD_IPS[@]}" "${NEW_ETCD_IPS[@]}")
            INITIAL_CLUSTER=""; for j in "${!ALL_HOSTNAMES_CFG[@]}"; do INITIAL_CLUSTER+="${ALL_HOSTNAMES_CFG[$j]}=https://{ALL_IPS_CFG[$j]}:2380,"; done; INITIAL_CLUSTER=${INITIAL_CLUSTER%,}
            sed -i "s|^ETCD_NAME=.*|ETCD_NAME=${name}|" "$new_env_file"
            sed -i "s|^ETCD_INITIAL_ADVERTISE_PEER_URLS=.*|ETCD_INITIAL_ADVERTISE_PEER_URLS=https://{ip}:2380|" "$new_env_file"
            sed -i "s|^ETCD_ADVERTISE_CLIENT_URLS=.*|ETCD_ADVERTISE_CLIENT_URLS=https://{ip}:2379|" "$new_env_file"
            sed -i "s|^ETCD_LISTEN_PEER_URLS=.*|ETCD_LISTEN_PEER_URLS=https://{ip}:2380|" "$new_env_file"
            sed -i "s|^ETCD_LISTEN_CLIENT_URLS=.*|ETCD_LISTEN_CLIENT_URLS=https://{ip}:2379,https://127.0.0.1:2379|" "$new_env_file"
            sed -i "s|^ETCD_INITIAL_CLUSTER=.*|ETCD_INITIAL_CLUSTER=\"${INITIAL_CLUSTER}\"|" "$new_env_file"
            sed -i "s|^ETCD_INITIAL_CLUSTER_STATE=.*|ETCD_INITIAL_CLUSTER_STATE=existing|" "$new_env_file"
            sed -i "s|member-.*\.pem|member-${name}.pem|" "$new_env_file"
            sed -i "s|member-.*-key\.pem|member-${name}-key.pem|" "$new_env_file"
            sed -i "s|admin-.*\.pem|admin-${name}.pem|" "$new_env_file"
            sed -i "s|admin-.*-key\.pem|admin-${name}-key.pem|" "$new_env_file"
            upload_file_if_changed "$new_env_file" "$name" "$ETCD_ENV_FILE"
            upload_file_if_changed "${TMP_DIR}/etcd.service.template" "$name" "$ETCD_SERVICE_FILE"
            start_etcd_service "$name"
        fi
        log_info "--- 节点 ${name} 部署完成 ---"
    done
}

task_verify_cluster_health() {
    log_step "验证集群健康状态"
    local source_host="${OLD_ETCD_HOSTNAMES[0]}"
    ALL_IPS_HEALTH=("${OLD_ETCD_IPS[@]}" "${NEW_ETCD_IPS[@]}")
    ALL_ENDPOINTS=""; for ip in "${ALL_IPS_HEALTH[@]}"; do ALL_ENDPOINTS+="https://{ip}:2379,"; done; ALL_ENDPOINTS=${ALL_ENDPOINTS%,}
    local cmd="ETCDCTL_API=3 etcdctl --endpoints=${ALL_ENDPOINTS} --cacert=${ETCD_CERT_DIR}/ca.pem --cert=${ETCD_CERT_DIR}/admin-${source_host}.pem --key=${ETCD_CERT_DIR}/admin-${source_host}-key.pem endpoint health --cluster"
    log_info "从 ${source_host} 执行健康检查..."
    if ! remote_exec "$source_host" "$cmd"; then log_error "集群健康检查失败！"; fi
    log_info "健康检查通过。"
}

task_update_old_nodes() {
    log_step "滚动更新现有节点的配置和证书"
    for i in "${!OLD_ETCD_HOSTNAMES[@]}"; do
        local name="${OLD_ETCD_HOSTNAMES[$i]}"
        local ip="${OLD_ETCD_IPS[$i]}"
        log_info "--- 开始更新节点 ${name} ---"
        
        for cert_type in member admin node; do
             upload_file_if_changed "${LOCAL_CERT_DIR}/${cert_type}-${name}.pem" "$name" "${ETCD_CERT_DIR}/${cert_type}-${name}.pem"
             upload_file_if_changed "${LOCAL_CERT_DIR}/${cert_type}-${name}-key.pem" "$name" "${ETCD_CERT_DIR}/${cert_type}-${name}-key.pem"
        done

        ALL_HOSTNAMES_CFG_OLD=("${OLD_ETCD_HOSTNAMES[@]}" "${NEW_ETCD_HOSTNAMES[@]}"); ALL_IPS_CFG_OLD=("${OLD_ETCD_IPS[@]}" "${NEW_ETCD_IPS[@]}")
        INITIAL_CLUSTER_OLD=""; for j in "${!ALL_HOSTNAMES_CFG_OLD[@]}"; do INITIAL_CLUSTER_OLD+="${ALL_HOSTNAMES_CFG_OLD[$j]}=https://{ALL_IPS_CFG_OLD[$j]}:2380,"; done; INITIAL_CLUSTER_OLD=${INITIAL_CLUSTER_OLD%,}
        local update_cmd="sed -i 's|^ETCD_INITIAL_CLUSTER=.*|ETCD_INITIAL_CLUSTER=\"${INITIAL_CLUSTER_OLD}\"|' ${ETCD_ENV_FILE}"
        remote_exec "$name" "$update_cmd"

        restart_etcd_service "$name"
        
        task_verify_cluster_health
        log_info "--- 节点 ${name} 更新完成 ---"
    done
}

# --- 主逻辑 ---
main() {
    if [[ ${#NEW_ETCD_HOSTNAMES[@]} -eq 0 ]]; then
        log_warn "在 config.sh 中没有配置新的 ETCD 节点。脚本将退出。"
        exit 0
    fi
    
    task_prepare_workspace
    task_generate_all_certs
    task_register_new_members
    task_deploy_new_nodes

    task_verify_cluster_health
    read -p "新节点已加入并健康。按 Enter 键继续滚动更新老节点的配置和证书..."

    task_update_old_nodes
    
    log_info "\n${GREEN}所有节点更新完毕。执行最终健康检查...${NC}"
    task_verify_cluster_health

    log_info "\n${GREEN}ETCD 集群扩容成功！所有节点的配置和证书均已更新并完全一致。🎉${NC}"
}

main