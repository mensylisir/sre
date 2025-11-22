#!/usr/bin/env bash
set -e -o pipefail

source ./config.sh

SSH_OPTIONS="-i ${SSH_IDENTITY_FILE} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
NEW_HOSTS_ENTRIES="temp_new_hosts_entries.txt"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
function info { echo -e "\n${GREEN}$*${NC}"; }
function warn { echo -e "${YELLOW}$*${NC}"; }
function error { echo -e "${RED}$*${NC}"; exit 1; }

main() {
  info "== [步骤 4/4] 开始将新节点信息同步到所有老节点 =="

  warn "[任务 4.1] 准备新节点的 hosts 条目..."
  NEW_NODES_INFO=""
  for ip in "${NEW_WORKER_IPS[@]}"; do
    hostname_info=$(ssh ${SSH_OPTIONS} ${SSH_USER}@${ip} "fqdn=\$(hostname); short=\$(hostname -s); [ -z \"\$fqdn\" ] && fqdn=\$short; echo \"\$fqdn \$short\"")
    [ $? -ne 0 ] && error "无法获取节点 ${ip} 的主机名，请检查网络和SSH配置。"
    IFS=' ' read -r fqdn short_name <<< "${hostname_info}"
    NEW_NODES_INFO+="${ip}  ${fqdn}.cluster.local ${short_name}\n"
  done
  echo -e "${NEW_NODES_INFO}" > ${NEW_HOSTS_ENTRIES}
  sed -i '/^$/d' ${NEW_HOSTS_ENTRIES}
  
  # Append the END marker so it is preserved after sed replacement
  echo "# kubekey hosts END" >> ${NEW_HOSTS_ENTRIES}
  
  echo "  -> 新节点条目已生成。"

  warn "[任务 4.2] 获取所有老节点的 IP 列表..."
  ALL_EXISTING_NODE_IPS=($(ssh ${SSH_OPTIONS} ${SSH_USER}@${MASTER_IP} "KUBECONFIG=${REMOTE_KUBECONFIG_PATH} kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type==\"InternalIP\")].address}'"))
  for new_ip in "${NEW_WORKER_IPS[@]}"; do
    ALL_EXISTING_NODE_IPS=("${ALL_EXISTING_NODE_IPS[@]/$new_ip/}")
#!/usr/bin/env bash
set -e -o pipefail

source ./config.sh

SSH_OPTIONS="-i ${SSH_IDENTITY_FILE} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
NEW_HOSTS_ENTRIES="temp_new_hosts_entries.txt"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
function info { echo -e "\n${GREEN}$*${NC}"; }
function warn { echo -e "${YELLOW}$*${NC}"; }
function error { echo -e "${RED}$*${NC}"; exit 1; }

main() {
  info "== [步骤 4/4] 开始将新节点信息同步到所有老节点 =="

  warn "[任务 4.1] 准备新节点的 hosts 条目..."
  NEW_NODES_INFO=""
  for ip in "${NEW_WORKER_IPS[@]}"; do
    hostname_info=$(ssh ${SSH_OPTIONS} ${SSH_USER}@${ip} "fqdn=\$(hostname); short=\$(hostname -s); [ -z \"\$fqdn\" ] && fqdn=\$short; echo \"\$fqdn \$short\"")
    [ $? -ne 0 ] && error "无法获取节点 ${ip} 的主机名，请检查网络和SSH配置。"
    IFS=' ' read -r fqdn short_name <<< "${hostname_info}"
    NEW_NODES_INFO+="${ip}  ${fqdn}.cluster.local ${short_name}\n"
  done
  echo -e "${NEW_NODES_INFO}" > ${NEW_HOSTS_ENTRIES}
  sed -i '/^$/d' ${NEW_HOSTS_ENTRIES}
  
  # Append the END marker so it is preserved after sed replacement
  echo "# kubekey hosts END" >> ${NEW_HOSTS_ENTRIES}
  
  echo "  -> 新节点条目已生成。"

  warn "[任务 4.2] 获取所有老节点的 IP 列表..."
  ALL_EXISTING_NODE_IPS=($(ssh ${SSH_OPTIONS} ${SSH_USER}@${MASTER_IP} "KUBECONFIG=${REMOTE_KUBECONFIG_PATH} kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type==\"InternalIP\")].address}'"))
  for new_ip in "${NEW_WORKER_IPS[@]}"; do
    ALL_EXISTING_NODE_IPS=("${ALL_EXISTING_NODE_IPS[@]/$new_ip/}")
  done
  echo "  -> 找到 ${#ALL_EXISTING_NODE_IPS[@]} 个老节点需要更新。"

  warn "[任务 4.3] 开始将新条目同步到老节点..."
  for node_ip in "${ALL_EXISTING_NODE_IPS[@]}"; do
    if [ -z "$node_ip" ]; then continue; fi
    echo "  -> 正在更新节点 ${node_ip}..."
    scp ${SSH_OPTIONS} ${NEW_HOSTS_ENTRIES} ${SSH_USER}@${node_ip}:/tmp/
    
    # Backup /etc/hosts
    ssh ${SSH_OPTIONS} ${SSH_USER}@${node_ip} "cp /etc/hosts /etc/hosts.bak.\$(date +%F_%H%M%S)"
    
    ssh ${SSH_OPTIONS} ${SSH_USER}@${node_ip} "sed -i '/# kubekey hosts END/e cat /tmp/${NEW_HOSTS_ENTRIES}' /etc/hosts"
  done

  rm -f ${NEW_HOSTS_ENTRIES}
  info "\n== 所有老节点的 hosts 文件已更新完毕！集群扩容完成。 =="
}
main "$@"