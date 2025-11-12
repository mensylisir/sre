#!/bin/bash
set -e
source 00-config.sh
source lib.sh

log "====== 第0步: 准备工作开始 ======"

# 1. 创建工作区并动态获取主机名
log "创建工作区目录: ${WORKSPACE_DIR}"
mkdir -p "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}"

if [ ! -f "${HOSTS_FILE}" ]; then
    log "错误: ${HOSTS_FILE} 文件未找到!"
    exit 1
fi
ALL_NODES=($(cat ${HOSTS_FILE} | grep -vE '^\s*#|^\s*$' | sort -u))
log "从 ${HOSTS_FILE} 加载了 ${#ALL_NODES[@]} 个节点 IP。"

log "--- 正在通过 SSH 动态获取所有节点的主机名 ---"
declare -A IP_TO_HOSTNAME
for node_ip in "${ALL_NODES[@]}"; do
    hostname=$(ssh ${SSH_OPTS} ${SSH_USER}@${node_ip} "hostname -s" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$hostname" ]; then
        log "错误: 无法连接到节点 ${node_ip} 或获取其主机名！请检查网络和 SSH 密钥。"
        exit 1
    fi
    IP_TO_HOSTNAME["${node_ip}"]="${hostname}"
    log "节点 ${node_ip} -> ${hostname}"
done
log "--- 主机名映射构建完成 ---"

# 2. 拉取旧配置
log "--- 从线上集群拉取当前配置到 'old' 目录 ---"
for node_ip in "${ALL_NODES[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log "为节点 ${hostname} (${node_ip}) 创建目录结构并拉取文件"
    mkdir -p "${hostname}/{old,new,bundle}"
    
    sync_from_remote "${node_ip}" "${REMOTE_KUBELET_CONF}" "${hostname}/old/kubelet.conf"

    if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]]; then
        sync_from_remote "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/" "${hostname}/old/kubernetes/"
        find "${hostname}/old/kubernetes/" -name "*.conf" -exec cp {} "${hostname}/old/" \;
    fi
    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        sync_from_remote "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/" "${hostname}/old/etcd-ssl/"
    fi
done

# 3. 生成新 CAs (使用最终、正确的命名和目录结构)
log "--- 生成所有新的 CA 证书 ---"
mkdir -p "new-cas/kubernetes" "new-cas/etcd" "new-cas/front-proxy"
log "生成 Kubernetes CA..."
generate_ca "new-cas/kubernetes/ca.key" "new-cas/kubernetes/ca.crt" "${K8S_CA_SUBJECT}"
log "生成 Etcd CA..."
generate_ca "new-cas/etcd/ca-key.pem" "new-cas/etcd/ca.pem" "${ETCD_CA_SUBJECT}"
log "生成 Front Proxy CA..."
generate_ca "new-cas/front-proxy/ca.key" "new-cas/front-proxy/ca.crt" "${FRONT_PROXY_CA_SUBJECT}"

# 4. 智能提取 SANs
log "--- 从旧证书中智能提取 SANs ---"
FIRST_MASTER_HOSTNAME=${IP_TO_HOSTNAME[${MASTER_NODES[0]}]}
FIRST_ETCD_HOSTNAME=${IP_TO_HOSTNAME[${ETCD_NODES[0]}]}
K8S_APISERVER_SANS=$(openssl x509 -in ${FIRST_MASTER_HOSTNAME}/old/kubernetes/pki/apiserver.crt -noout -text | grep -A1 "Subject Alternative Name" | tail -n1 | sed 's/^[ \t]*//' | tr -d ' ')
ETCD_SANS=$(openssl x509 -in ${FIRST_ETCD_HOSTNAME}/old/etcd-ssl/admin-${FIRST_ETCD_HOSTNAME}.pem -noout -text | grep -A1 "Subject Alternative Name" | tail -n1 | sed 's/^[ \t]*//' | tr -d ' ')
log "提取到 K8s APIServer SANs: ${K8S_APISERVER_SANS}"
log "提取到 ETCD SANs: ${ETCD_SANS}"

# 5. 生成所有新叶子证书并准备 'new' 目录
log "--- 生成所有新的叶子证书并准备 'new' 目录 ---"
for node_ip in "${ALL_NODES[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log "为节点 ${hostname} 准备 'new' 目录"
    mkdir -p "${hostname}/new/"
    cp "${hostname}/old/kubelet.conf" "${hostname}/new/"

    if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]]; then
        mkdir -p "${hostname}/new/kubernetes/pki"
        cp "${hostname}/old/admin.conf" "${hostname}/new/"
        cp "${hostname}/old/controller-manager.conf" "${hostname}/new/"
        cp "${hostname}/old/scheduler.conf" "${hostname}/new/"

        cp new-cas/kubernetes/ca.key ${hostname}/new/kubernetes/pki/ca.key
        cp new-cas/kubernetes/ca.crt ${hostname}/new/kubernetes/pki/ca.crt
        cp new-cas/front-proxy/ca.key ${hostname}/new/kubernetes/pki/front-proxy-ca.key
        cp new-cas/front-proxy/ca.crt ${hostname}/new/kubernetes/pki/front-proxy-ca.crt
        
        generate_leaf_cert new-cas/kubernetes/ca.crt new-cas/kubernetes/ca.key \
            "${hostname}/new/kubernetes/pki/apiserver.key" "${hostname}/new/kubernetes/pki/apiserver.crt" \
            "/CN=kube-apiserver" "${K8S_APISERVER_SANS}" "serverAuth"
        generate_leaf_cert new-cas/kubernetes/ca.crt new-cas/kubernetes/ca.key \
            "${hostname}/new/kubernetes/pki/apiserver-kubelet-client.key" "${hostname}/new/kubernetes/pki/apiserver-kubelet-client.crt" \
            "/CN=kube-apiserver-kubelet-client" "" "clientAuth" "system:masters"
        generate_leaf_cert new-cas/front-proxy/ca.crt new-cas/front-proxy/ca.key \
            "${hostname}/new/kubernetes/pki/front-proxy-client.key" "${hostname}/new/kubernetes/pki/front-proxy-client.crt" \
            "/CN=front-proxy-client" "" "clientAuth"
        openssl genrsa -out "${hostname}/new/kubernetes/pki/sa.key" 2048
        openssl rsa -in "${hostname}/new/kubernetes/pki/sa.key" -pubout -out "${hostname}/new/kubernetes/pki/sa.pub"
        if [ -f "${hostname}/old/kubernetes/pki/keycloak.crt" ]; then cp "${hostname}/old/kubernetes/pki/keycloak.crt" "${hostname}/new/kubernetes/pki/"; fi
    fi
    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        mkdir -p "${hostname}/new/etcd-ssl"
        cp new-cas/etcd/ca-key.pem ${hostname}/new/etcd-ssl/ca-key.pem
        cp new-cas/etcd/ca.pem ${hostname}/new/etcd-ssl/ca.pem
        local_etcd_sans="DNS:${hostname},IP:${node_ip}"
        generate_leaf_cert new-cas/etcd/ca.pem new-cas/etcd/ca-key.pem \
            "${hostname}/new/etcd-ssl/member-${hostname}-key.pem" "${hostname}/new/etcd-ssl/member-${hostname}.pem" \
            "/CN=etcd-member-${hostname}" "${local_etcd_sans}" "serverAuth,clientAuth"
        generate_leaf_cert new-cas/etcd/ca.pem new-cas/etcd/ca-key.pem \
            "${hostname}/new/etcd-ssl/admin-${hostname}-key.pem" "${hostname}/new/etcd-ssl/admin-${hostname}.pem" \
            "/CN=etcd-admin-${hostname}" "${ETCD_SANS}" "serverAuth,clientAuth"
        generate_leaf_cert new-cas/etcd/ca.pem new-cas/etcd/ca-key.pem \
            "${hostname}/new/etcd-ssl/node-${hostname}-key.pem" "${hostname}/new/etcd-ssl/node-${hostname}.pem" \
            "/CN=etcd-node-${hostname}" "${ETCD_SANS}" "serverAuth,clientAuth"
    fi
done

# 6. 生成 'bundle' 过渡阶段配置
log "--- 生成 'bundle' 过渡阶段配置 ---"
cat ${FIRST_MASTER_HOSTNAME}/old/kubernetes/pki/ca.crt new-cas/kubernetes/ca.crt > k8s-bundle.crt
cat ${FIRST_ETCD_HOSTNAME}/old/etcd-ssl/ca.pem new-cas/etcd/ca.pem > etcd-bundle.pem
K8S_BUNDLE_CA_BASE64=$(cat k8s-bundle.crt | base64 | tr -d '\n')

for node_ip in "${ALL_NODES[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log "为节点 ${hostname} 准备 'bundle' 目录"
    cp -r "${hostname}/old/"* "${hostname}/bundle/"
    update_kubeconfig_ca "${hostname}/bundle/kubelet.conf" "${K8S_BUNDLE_CA_BASE64}"
    if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]]; then
        update_kubeconfig_ca "${hostname}/bundle/admin.conf" "${K8S_BUNDLE_CA_BASE64}"
        update_kubeconfig_ca "${hostname}/bundle/controller-manager.conf" "${K8S_BUNDLE_CA_BASE64}"
        update_kubeconfig_ca "${hostname}/bundle/scheduler.conf" "${K8S_BUNDLE_CA_BASE64}"
        cp k8s-bundle.crt "${hostname}/bundle/kubernetes/pki/ca.crt"
    fi
    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        cp etcd-bundle.pem "${hostname}/bundle/etcd-ssl/ca.pem"
    fi
done

# 7. 生成 IP-Hostname 映射文件供后续脚本使用
log "--- 生成 ip_hostname_map.txt 文件 ---"
> ip_hostname_map.txt
for ip in "${!IP_TO_HOSTNAME[@]}"; do echo "$ip ${IP_TO_HOSTNAME[$ip]}" >> ip_hostname_map.txt; done

# 8. 清理临时文件
log "--- 清理临时 CA bundle 文件 ---"
rm -f k8s-bundle.crt etcd-bundle.pem

log "====== 准备工作完成！所有配置文件已在 ${WORKSPACE_DIR} 中生成 ======"