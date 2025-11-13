#!/bin/bash
set -e
source 00-config.sh
source lib.sh

STAGE="new"
ACTION_DESC="应用 ${STAGE} 阶段最终配置 (移除旧CA信任)"

cd "${WORKSPACE_DIR}" || { log "错误: 工作区目录 ${WORKSPACE_DIR} 不存在!"; exit 1; }

if [ ! -f "ip_hostname_map.txt" ]; then log "错误: ip_hostname_map.txt 未找到. 请先执行 01-prepare.sh"; exit 1; fi
declare -A IP_TO_HOSTNAME
while read -r ip host; do IP_TO_HOSTNAME["$ip"]="$host"; done < ip_hostname_map.txt


ALL_IPS_SORTED_SET=$(printf "%s\n" "${ALL_NODES[@]}" | sort -u)
MASTER_IPS_SORTED_SET=$(printf "%s\n" "${MASTER_NODES[@]}" | sort -u)
ETCD_IPS_SORTED_SET=$(printf "%s\n" "${ETCD_NODES[@]}" | sort -u)
WORKER_NODES_IP=($(comm -23 <(echo "${ALL_IPS_SORTED_SET}") <(echo "${MASTER_IPS_SORTED_SET}")))
CONTROL_PLANE_IPS_SORTED_SET=$(printf "%s\n%s\n" "${MASTER_NODES[@]}" "${ETCD_NODES[@]}" | sort -u)
CONTROL_PLANE_NODES=(${CONTROL_PLANE_IPS_SORTED_SET})

FIRST_MASTER_IP=${MASTER_NODES[0]}
if [ -z "${FIRST_MASTER_IP}" ]; then log "错误: MASTER_NODES 列表为空!"; exit 1; fi
FIRST_MASTER_HOSTNAME=${IP_TO_HOSTNAME[${FIRST_MASTER_IP}]}

KUBECONFIG_PATH="${WORKSPACE_DIR}/${FIRST_MASTER_HOSTNAME}/bundle/admin.conf" 
if [ ! -f "${KUBECONFIG_PATH}" ]; then log "错误: 找不到用于 kubectl 的 kubeconfig 文件: ${KUBECONFIG_PATH}"; exit 1; fi
export KUBECONFIG="${KUBECONFIG_PATH}"
log "已将 KUBECONFIG 环境变量设置为: ${KUBECONFIG_PATH}"
log "测试 kubectl 连接..."
kubectl get nodes > /dev/null
if [ $? -ne 0 ]; then log "错误: 使用 ${KUBECONFIG_PATH} 无法连接到 Kubernetes 集群！请检查配置。"; exit 1; fi

confirm_action "${ACTION_DESC}"

log "====== ${ACTION_DESC} 开始 ======"

log "--- 滚动更新 Worker 节点 ---"
for node_ip in "${WORKER_NODES_IP[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log ">>> 处理 Worker 节点: ${hostname} (${node_ip})"
    sync_to_remote "${hostname}/${STAGE}/kubelet.conf" "${node_ip}" "${REMOTE_KUBELET_CONF}"
    log "为 Worker ${hostname} 同步最终 CA 证书 (以备不时之需)"
    run_remote "${node_ip}" "mkdir -p ${REMOTE_K8S_CONFIG_DIR}/pki"
    sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/ca.crt" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/ca.crt"
    run_remote "${node_ip}" "systemctl restart kubelet"
    wait_for_node_ready "${node_ip}"
done

log "--- 滚动更新控制平面节点 (Master 和 Etcd) ---"
for node_ip in "${CONTROL_PLANE_NODES[@]}"; do
    hostname=${IP_TO_HOSTNAME[${node_ip}]}
    log ">>> 处理控制平面节点: ${hostname} (${node_ip})"
    
    if [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "该节点是 Master, 同步 K8s 的最终 CA 和 conf 文件..."
        sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/ca.crt" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/"
        sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/ca.key" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/"
        sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/front-proxy-ca.crt" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/"
        sync_to_remote "${hostname}/${STAGE}/kubernetes/pki/front-proxy-ca.key" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/pki/"
        sync_to_remote "${hostname}/${STAGE}/admin.conf" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/controller-manager.conf" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/scheduler.conf" "${node_ip}" "${REMOTE_K8S_CONFIG_DIR}/"
    fi

    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]] || [[ " ${MASTER_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "该节点是 Etcd, 同步 etcd 的最终 CA..."
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/ca.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
        sync_to_remote "${hostname}/${STAGE}/etcd-ssl/ca-key.pem" "${node_ip}" "${REMOTE_ETCD_SSL_DIR}/"
    fi

    log "同步 Kubelet 最终配置..."
    sync_to_remote "${hostname}/${STAGE}/kubelet.conf" "${node_ip}" "${REMOTE_KUBELET_CONF}"
    
    log "重启 kubelet 以完成最终切换..."
    run_remote "${node_ip}" "systemctl restart kubelet"
    wait_for_node_ready "${node_ip}"
    log "在节点 ${hostname} 上的最终配置已应用, 等待15秒观察状态。"

    if [[ " ${ETCD_NODES[@]} " =~ " ${node_ip} " ]]; then
        log "节点最终配置已应用。等待15秒让 Etcd 集群稳定..."
        sleep 15
        local check_ca_path="${hostname}/new/etcd-ssl/ca.pem"
        local check_cert_path="${hostname}/new/etcd-ssl/admin-${hostname}.pem"
        local check_key_path="${hostname}/new/etcd-ssl/admin-${hostname}-key.pem"
        
        check_etcd_health "${node_ip}" "${check_ca_path}" "${check_cert_path}" "${check_key_path}"
    else
        log "节点最终配置已应用。等待15秒观察控制平面 Pod 状态..."
        sleep 15
    fi
done

NEW_KUBECONFIG_PATH="${WORKSPACE_DIR}/${FIRST_MASTER_HOSTNAME}/new/admin.conf"
log "====== CA 轮换成功! ======"
log "请注意: 您本地的 kubeconfig 文件可能已失效。"
log "请使用新的配置文件进行后续操作: ${NEW_KUBECONFIG_PATH}"
log "您可以运行以下命令来更新您的配置:"
log "cp ${NEW_KUBECONFIG_PATH} ~/.kube/config"

log "====== ${ACTION_DESC} 完成！CA 证书更换流程已全部结束。 ======"