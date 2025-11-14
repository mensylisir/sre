#!/bin/bash

# ==============================================================================
# 任务 1: 初始化操作系统 (V5 - 最终正确版)
# ==============================================================================

set -e
source ./lib.sh

# --- 1. 自动发现/获取所有配置 ---
fetch_resources

# --- 2. 定位并分发 ISO 文件到【新节点】 ---
log_info "正在定位并分发操作系统 ISO 仓库文件..."
OS_REPO_ISO_PATH=$(find ${ARTIFACT_PATH}/repository -name "*.iso" | head -n 1)

if [ ! -f "$OS_REPO_ISO_PATH" ]; then
    log_error "在 Artifact 的 'repository' 目录中未找到任何 .iso 文件！"
    exit 1
fi
log_success "已定位 ISO 文件: ${OS_REPO_ISO_PATH}"

REMOTE_ISO_TMP_DIR="/tmp/kk-iso-repo-$$"
pids=()
for node_info in "${ALL_NODES[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    user=$(echo "$node_info" | awk '{print $3}')
    (
        echo "  -> 正在向新节点 ${ip} 分发 ISO 文件..."
        $SSH_CMD ${user}@${ip} "mkdir -p ${REMOTE_ISO_TMP_DIR}"
        $SCP_CMD "${OS_REPO_ISO_PATH}" "${user}@${ip}:${REMOTE_ISO_TMP_DIR}/repo.iso"
        if [ $? -eq 0 ]; then echo -e "  \e[32m✔\e[0m 节点 ${ip} ISO 分发成功。"; else echo -e "  \e[31m✖\e[0m 节点 ${ip} ISO 分发失败。"; fi
    ) &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
log_success "所有新节点 ISO 文件分发完毕。"


# --- 3. 在【新节点】上执行完整的初始化脚本 (100% 参照 initOS.sh) ---
read -r -d '' os_init_script <<'EOF'
set -e
echo "  - 正在执行完整的 initOS 逻辑..."

# --- Part A: 使用 ISO 安装基础包 ---
REMOTE_ISO_TMP_DIR="/tmp/kk-iso-repo-$$"
ISO_MOUNT_POINT="/mnt/kubekey-repo"

echo "  - 正在配置本地 ISO 软件源..."
mkdir -p ${ISO_MOUNT_POINT}
mount -o loop ${REMOTE_ISO_TMP_DIR}/repo.iso ${ISO_MOUNT_POINT}
if command -v apt-get &> /dev/null; then
    mv /etc/apt/sources.list /etc/apt/sources.list.bak
    echo "deb [trusted=yes] file://${ISO_MOUNT_POINT} ./" > /etc/apt/sources.list
    apt-get update -qq
    echo "  - 正在安装基础软件包 (apt)..."
    apt-get install -y -qq socat conntrack ipset ebtables chrony ipvsadm curl
    mv /etc/apt/sources.list.bak /etc/apt/sources.list
    apt-get update -qq
elif command -v yum &> /dev/null; then
    mkdir -p /etc/yum.repos.d.bak
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d.bak/
    echo -e "[kubekey-local]\nname=KubeKey Local Repo\nbaseurl=file://${ISO_MOUNT_POINT}\nenabled=1\ngpgcheck=0" > /etc/yum.repos.d/kubekey-local.repo
    yum clean all > /dev/null
    echo "  - 正在安装基础软件包 (yum)..."
    yum install -y -q socat conntrack-tools ipset ebtables chrony ipvsadm curl
    rm -f /etc/yum.repos.d/kubekey-local.repo
    mv /etc/yum.repos.d.bak/*.repo /etc/yum.repos.d/
    rm -rf /etc/yum.repos.d.bak
    yum clean all > /dev/null
else
    echo "  - 警告: 无法自动安装基础软件包。"
fi
umount ${ISO_MOUNT_POINT}
rm -rf ${REMOTE_ISO_TMP_DIR}
rmdir ${ISO_MOUNT_POINT}
echo "  - 本地 ISO 软件源已清理。"

# --- Part B: 执行所有系统配置 (来自您提供的 initOS.sh) ---
swapoff -a
sed -i '/^[^#]*swap*/s/^/\#/g' /etc/fstab

if [ -f /etc/selinux/config ]; then 
  sed -ri 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
fi
if command -v setenforce &> /dev/null; then
  setenforce 0
fi

# 使用独立的 sysctl 配置文件，更干净
cat > /etc/sysctl.d/99-kubekey.conf <<EOT
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_local_reserved_ports = 30000-32767
vm.max_map_count = 262144
vm.swappiness = 1
fs.inotify.max_user_instances = 524288
kernel.pid_max = 65535
net.ipv4.tcp_tw_recycle = 0
EOT
sysctl --system > /dev/null 2>&1

systemctl stop firewalld > /dev/null 2>&1 || true
systemctl disable firewalld > /dev/null 2>&1 || true
systemctl stop ufw > /dev/null 2>&1 || true
systemctl disable ufw > /dev/null 2>&1 || true

modprobe br_netfilter
modprobe overlay
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
# 尝试加载 nf_conntrack_ipv4，如果失败则加载 nf_conntrack
modprobe nf_conntrack_ipv4 > /dev/null 2>&1 || modprobe nf_conntrack

# 创建 modules-load.d 文件
cat > /etc/modules-load.d/kubekey-k8s.conf <<EOT
br_netfilter
overlay
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack_ipv4
nf_conntrack
EOT

update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || true
update-alternatives --set arptables /usr/sbin/arptables-legacy >/dev/null 2>&1 || true
update-alternatives --set ebtables /usr/sbin/ebtables-legacy >/dev/null 2>&1 || true

ulimit -u 65535
ulimit -n 65535

echo 3 > /proc/sys/vm/drop_caches
EOF

execute_on_all_nodes "新节点操作系统环境初始化" "${os_init_script}"


# --- 4. 在【所有节点】(包括新旧) 上同步 hosts 文件 ---
log_info "开始在集群所有节点上同步 /etc/hosts 文件..."

# 4.1 重新构建完整的 hosts 块
new_nodes_hosts=""
for node_info in "${ALL_NODES[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    user=$(echo "$node_info" | awk '{print $3}')
    hostname_to_add=$($SSH_CMD ${user}@${ip} 'hostname')
    new_nodes_hosts+="${ip}  ${hostname_to_add}.cluster.local ${hostname_to_add}\n"
done
# 合并旧的 hosts (去掉首尾标记) 和新的 hosts
combined_hosts_body=$(echo -e "${EXISTING_HOSTS_BLOCK}\n${new_nodes_hosts}")
# 去重并格式化
unique_hosts_body=$(echo -e "${combined_hosts_body}" | awk '!seen[$1,$3]++')
final_hosts_content="# kubekey hosts BEGIN (Managed by script)\n${unique_hosts_body}\n# kubekey hosts END\n"

# 4.2 获取所有需要更新 hosts 的节点列表 (新节点 + 旧节点)
all_nodes_to_update_hosts=""
old_nodes_from_hosts=$(echo -e "$EXISTING_HOSTS_BLOCK" | awk '{print $1}')
for ip in $old_nodes_from_hosts; do
    all_nodes_to_update_hosts+="${ip} root\n" # 假设旧节点用户为 root
done
for node_info in "${ALL_NODES[@]}"; do
    ip=$(echo "$node_info" | awk '{print $1}')
    user=$(echo "$node_info" | awk '{print $3}')
    all_nodes_to_update_hosts+="${ip} ${user}\n"
done
unique_nodes_to_update=$(echo -e "${all_nodes_to_update_hosts}" | sort -u -k1,1)

# 4.3 并行执行 hosts 更新
encoded_hosts=$(echo -e "${final_hosts_content}" | base64 -w 0)
update_hosts_script="sed -i '/# kubekey hosts BEGIN/,/# kubekey hosts END/d' /etc/hosts; echo '${encoded_hosts}' | base64 -d >> /etc/hosts;"

log_info "将在以下所有节点上刷新 hosts 文件:"
echo "${unique_nodes_to_update}"
pids=()
while read -r node_line; do
    ip=$(echo "$node_line" | awk '{print $1}')
    user=$(echo "$node_line" | awk '{print $2}')
    (
        echo "  -> 正在刷新节点 ${ip} 的 hosts..."
        $SSH_CMD ${user}@${ip} "sudo bash -c \"${update_hosts_script}\"" > /dev/null 2>&1 && \
        echo -e "  \e[32m✔\e[0m 节点 ${ip} hosts 更新成功。" || \
        echo -e "  \e[31m✖\e[0m 节点 ${ip} hosts 更新失败。"
    ) &
    pids+=($!)
done <<< "$unique_nodes_to_update"
for pid in "${pids[@]}"; do wait "$pid"; done
log_success "所有节点的 hosts 文件同步完毕。"