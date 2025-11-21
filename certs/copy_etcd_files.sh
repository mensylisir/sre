#!/bin/bash
set -e
set -o pipefail

# --- 配置区域 ---


OLD_ETCD_NODES=("192.168.1.10" "192.168.1.11" "192.168.1.12")

NEW_ETCD_NODES=("192.168.1.20" "192.168.1.21" "192.168.1.22")

SSH_USER="root"

FILES_TO_COPY=(
    "/etc/etcd.env"
    "/usr/local/bin/etcd"
    "/usr/local/bin/etcdctl"
    "/etc/systemd/system/etcd.service"
)


SOURCE_NODE=${OLD_ETCD_NODES[0]}

if [ -z "$SOURCE_NODE" ]; then
    echo "错误：旧 Etcd 节点列表 (OLD_ETCD_NODES) 为空，无法确定源节点。"
    exit 1
fi

if [ ${#NEW_ETCD_NODES[@]} -eq 0 ]; then
    echo "错误：新 Etcd 节点列表 (NEW_ETCD_NODES) 为空，没有目标节点。"
    exit 1
fi

echo "================================================="
echo "开始将 Etcd 文件从 ${SOURCE_NODE} 复制到新节点..."
echo "目标新节点: ${NEW_ETCD_NODES[*]}"
echo "================================================="
echo

for target_node in "${NEW_ETCD_NODES[@]}"; do
    echo ">>> 正在处理新节点: ${target_node}"

    echo "    - 检查到 ${target_node} 的连接..."
    if ! ping -c 1 -W 2 ${target_node} &> /dev/null; then
        echo "    - 错误：无法 PING通 ${target_node}，请检查网络或IP配置。跳过此节点。"
        continue
    fi
    echo "    - 连接正常。"

    for file_path in "${FILES_TO_COPY[@]}"; do
        dest_dir=$(dirname "${file_path}")

        echo "    - 正在复制文件: ${file_path}"

        echo "      (步骤1/2) 在 ${target_node} 上确保目录 ${dest_dir} 存在..."
        ssh "${SSH_USER}@${target_node}" "mkdir -p ${dest_dir}"


        temp_file="/tmp/$(basename ${file_path}).$RANDOM"
        echo "      (步骤2/2) 从 ${SOURCE_NODE} 复制到 ${target_node}..."
        
        scp "${SSH_USER}@${SOURCE_NODE}:${file_path}" "${temp_file}"
        scp "${temp_file}" "${SSH_USER}@${target_node}:${file_path}"
        rm "${temp_file}"

        echo "      -> 复制成功。"
    done
    
    echo "    - 正在设置 ${target_node} 上文件的权限..."
    ssh "${SSH_USER}@${target_node}" "chmod 755 /usr/local/bin/etcd /usr/local/bin/etcdctl"
    
    echo ">>> 节点 ${target_node} 处理完毕。"
    echo
done

echo "================================================="
echo "✅ 所有文件已成功复制到所有新节点！"
echo
echo "下一步【非常重要】的操作："
echo "请手动 SSH 登录到【每一个】新的 Etcd 节点，然后执行以下命令："
echo
echo "1. 重新加载 systemd 服务文件："
echo "   systemctl daemon-reload"
echo
echo "2. 启动 etcd 服务并设置为开机自启："
echo "   systemctl enable --now etcd.service"
echo
echo "3. 检查 etcd 服务状态，确保是 'active (running)'："
echo "   systemctl status etcd.service"
echo
echo "🔥【特别注意】🔥"
echo "如果你的 /etc/etcd.env 文件在每个节点上的配置【不一样】（例如 ETCD_NAME 或 ETCD_INITIAL_ADVERTISE_PEER_URLS），"
echo "请务必在启动服务【之前】，手动修改每个新节点上的 /etc/etcd.env 文件！"
echo "================================================="