#!/usr/bin/env bash
set -e -o pipefail


source ./config.sh

SSH_OPTIONS="-i ${SSH_IDENTITY_FILE} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
HOSTS_FILE_CONTENT="temp_hosts_content.txt"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
function info { echo -e "\n${GREEN}$*${NC}"; }
function warn { echo -e "${YELLOW}$*${NC}"; }
function error { echo -e "${RED}$*${NC}"; exit 1; }


init_disable_prereqs() {
cat << 'EOF'
set -e
echo "--> [INIT] 1/4: Disabling Prerequisites (Swap, SELinux, Firewall)..."
swapoff -a
sed -i '/^[^#]*swap*/s/^/#/g' /etc/fstab

if [ -f /etc/selinux/config ]; then
  sed -ri 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
fi
if command -v setenforce &> /dev/null; then setenforce 0; fi

systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
systemctl stop ufw 2>/dev/null || true
systemctl disable ufw 2>/dev/null || true
EOF
}

init_configure_sysctl() {
cat << 'EOF'
set -e
echo "--> [INIT] 2/4: Configuring Kernel Parameters (sysctl)..."
# Append desired settings to ensure they exist
{
    echo 'net.ipv4.ip_forward = 1'
    echo 'net.bridge.bridge-nf-call-arptables = 1'
    echo 'net.bridge.bridge-nf-call-ip6tables = 1'
    echo 'net.bridge.bridge-nf-call-iptables = 1'
    echo 'net.ipv4.ip_local_reserved_ports = 30000-32767'
    echo 'vm.max_map_count = 262144'
    echo 'vm.swappiness = 1'
    echo 'fs.inotify.max_user_instances = 524288'
    echo 'kernel.pid_max = 65535'
    if [ -e /proc/sys/net/ipv4/tcp_tw_recycle ]; then
      echo 'net.ipv4.tcp_tw_recycle = 0'
    fi
} >> /etc/sysctl.conf

# Use sed to enforce values, even if they were previously commented out
sed -r -i "s@^#{0,}\s*net.ipv4.tcp_tw_recycle\s*=\s*.\+@net.ipv4.tcp_tw_recycle = 0@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*net.ipv4.ip_forward\s*=\s*.\+@net.ipv4.ip_forward = 1@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*net.bridge.bridge-nf-call-arptables\s*=\s*.\+@net.bridge.bridge-nf-call-arptables = 1@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*net.bridge.bridge-nf-call-ip6tables\s*=\s*.\+@net.bridge.bridge-nf-call-ip6tables = 1@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*net.bridge.bridge-nf-call-iptables\s*=\s*.\+@net.bridge.bridge-nf-call-iptables = 1@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*net.ipv4.ip_local_reserved_ports\s*=\s*.\+@net.ipv4.ip_local_reserved_ports = 30000-32767@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*vm.max_map_count\s*=\s*.\+@vm.max_map_count = 262144@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*vm.swappiness\s*=\s*.\+@vm.swappiness = 1@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*fs.inotify.max_user_instances\s*=\s*.\+@fs.inotify.max_user_instances = 524288@g" /etc/sysctl.conf
sed -r -i "s@^#{0,}\s*kernel.pid_max\s*=\s*.\+@kernel.pid_max = 65535@g" /etc/sysctl.conf

# De-duplicate the sysctl.conf file for cleanliness
tmpfile="/tmp/$$.sysctl.tmp"
awk ' !x[$0]++' /etc/sysctl.conf > "$tmpfile"
mv "$tmpfile" /etc/sysctl.conf

sysctl --system >/dev/null
EOF
}

init_load_kernel_modules() {
cat << 'EOF'
set -e
echo "--> [INIT] 3/4: Loading Kernel Modules (br_netfilter, overlay, ip_vs)..."
mkdir -p /etc/modules-load.d

if modinfo br_netfilter > /dev/null 2>&1; then
   modprobe br_netfilter
   echo 'br_netfilter' > /etc/modules-load.d/kubekey-br_netfilter.conf
fi

if modinfo overlay > /dev/null 2>&1; then
   modprobe overlay
   echo 'overlay' >> /etc/modules-load.d/kubekey-br_netfilter.conf
fi

modprobe ip_vs; modprobe ip_vs_rr; modprobe ip_vs_wrr; modprobe ip_vs_sh

cat > /etc/modules-load.d/kube_proxy-ipvs.conf << EOL
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
EOL

if modprobe nf_conntrack_ipv4 1>/dev/null 2>&1; then
   echo 'nf_conntrack_ipv4' >> /etc/modules-load.d/kube_proxy-ipvs.conf
else
   modprobe nf_conntrack
   echo 'nf_conntrack' >> /etc/modules-load.d/kube_proxy-ipvs.conf
fi
EOF
}

init_finalize_settings() {
cat << 'EOF'
set -e
echo "--> [INIT] 4/4: Finalizing Settings (iptables, ulimit, cache)..."
update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || true
update-alternatives --set arptables /usr/sbin/arptables-legacy >/dev/null 2>&1 || true
update-alternatives --set ebtables /usr/sbin/ebtables-legacy >/dev/null 2>&1 || true

# Set limits for the current session
ulimit -u 65535
ulimit -n 65535

# Persist limits for future sessions
grep -q "root soft nofile 65535" /etc/security/limits.conf || echo "root soft nofile 65535" >> /etc/security/limits.conf
grep -q "root hard nofile 65535" /etc/security/limits.conf || echo "root hard nofile 65535" >> /etc/security/limits.conf

echo 3 > /proc/sys/vm/drop_caches
EOF
}


main() {
  info "== [步骤 1/4] 开始批量初始化新 Worker 节点 =="

  warn "[任务 1.1] 自动发现新节点主机名..."
  declare -A NEW_NODE_INFO
  for ip in "${NEW_WORKER_IPS[@]}"; do
    echo "  -> 正在发现节点 ${ip} 的主机名..."
    hostname_info=$(ssh ${SSH_OPTIONS} ${SSH_USER}@${ip} "fqdn=\$(hostname); short=\$(hostname -s); [ -z \"\$fqdn\" ] && fqdn=\$short; echo \"\$fqdn \$short\"")
    [ $? -ne 0 ] && error "无法获取节点 ${ip} 的主机名"
    NEW_NODE_INFO[$ip]=$hostname_info
    echo "  -> 发现: ${ip} -> ${hostname_info}"
  done

  warn "[任务 1.2] 动态生成【仅供新节点使用】的 hosts 文件..."

  echo "  -> [源1] 正在从 Master (${MASTER_IP}) 获取现有节点列表 (IP 和 主机名)..."
  EXISTING_NODES_INFO=$(ssh ${SSH_OPTIONS} ${SSH_USER}@${MASTER_IP} "KUBECONFIG=${REMOTE_KUBECONFIG_PATH} kubectl get nodes -o wide --no-headers | awk '{print \$6\"  \"\$1\".cluster.local \"\$1}'")
  [ -z "$EXISTING_NODES_INFO" ] && error "无法从 Master 获取节点信息！"


  OTHER_SERVICES_INFO=""; if [ ${#GLOBAL_SERVICES[@]} -gt 0 ]; then grep_pattern=$(printf "%s|" "${GLOBAL_SERVICES[@]}"); grep_pattern="${grep_pattern%|}"; OTHER_SERVICES_INFO=$(ssh ${SSH_OPTIONS} ${SSH_USER}@${EXISTING_WORKER_IP} "grep -E '${grep_pattern}' /etc/hosts" || true); fi
  NEW_NODES_INFO=""; for ip in "${NEW_WORKER_IPS[@]}"; do IFS=' ' read -r fqdn short_name <<< "${NEW_NODE_INFO[$ip]}"; NEW_NODES_INFO+="${ip}  ${fqdn}.cluster.local ${short_name}\n"; done

  {
    echo "# kubekey hosts BEGIN";
    echo -e "${EXISTING_NODES_INFO}";
    echo -e "${NEW_NODES_INFO}";
    echo -e "${OTHER_SERVICES_INFO}";
    echo "# kubekey hosts END";
  } > ${HOSTS_FILE_CONTENT}
  sed -i '/^$/d' ${HOSTS_FILE_CONTENT}
  echo "  -> 新节点专用的 Hosts 内容已生成。"

  warn "[任务 1.3] 在所有新节点上应用 hosts 并执行初始化..."
  INIT_PAYLOAD=$(init_disable_prereqs; init_configure_sysctl; init_load_kernel_modules; init_finalize_settings)
  for ip in "${NEW_WORKER_IPS[@]}"; do
    info "----------------- 正在初始化节点: ${ip} -----------------"
    scp ${SSH_OPTIONS} ${HOSTS_FILE_CONTENT} ${SSH_USER}@${ip}:/tmp/
    ssh ${SSH_OPTIONS} ${SSH_USER}@${ip} "sed -i ':a;\$!{N;ba};s@# kubekey hosts BEGIN.*# kubekey hosts END@@' /etc/hosts; sed -i '/^\$/N;/\n\$/N;//D' /etc/hosts; cat /tmp/${HOSTS_FILE_CONTENT} >> /etc/hosts"

    ssh ${SSH_OPTIONS} ${SSH_USER}@${ip} "${INIT_PAYLOAD}"
  done

  rm -f ${HOSTS_FILE_CONTENT}
  info "\n== 所有新节点的系统初始化已完成！接下来请执行 02-prepare-nodes.sh。 =="
}

main "$@"