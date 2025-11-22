# Kubernetes Add-Worker Scripts

本目录包含用于向现有 Kubernetes 集群添加新 Worker 节点的自动化脚本。
所有脚本设计为在 **堡垒机 (Bastion Host)** 上执行，通过 SSH 远程管理节点。

## 前置条件

1.  **执行环境**: 必须在堡垒机上运行。
2.  **SSH 访问**: 堡垒机必须拥有访问 Master 节点、现有 Worker 节点和新 Worker 节点的 SSH 私钥。
3.  **网络**:
    *   堡垒机 -> 所有节点 (SSH 22)
    *   新节点 -> Master 节点 (API Server 6443)
    *   新节点 -> 外网/内网源 (用于安装基础包)

## 配置说明

在执行任何脚本前，请先修改 `config.sh`：

```bash
# 新节点的 IP 地址列表
NEW_WORKER_IPS=(
    "10.5.67.101"
    "10.5.67.102"
)

# SSH 连接用户与私钥路径 (堡垒机上的路径)
SSH_USER="root"
SSH_IDENTITY_FILE="/var/tmp/ssh_config/huoguan"

# 现有集群信息
EXISTING_WORKER_IP="10.5.67.62"  # 用于复制二进制文件的源节点
MASTER_IP="10.5.67.176"          # Master 节点 IP
```

## 执行步骤

请按照顺序依次执行以下脚本：

### 1. 初始化节点
```bash
./01-init-nodes.sh
```
*   **功能**: 禁用 Swap/防火墙，调整内核参数，生成并分发 Hosts 文件。
*   **注意**: 脚本会自动从 Master 和现有节点抓取信息生成 Hosts。

### 2. 准备环境
```bash
./02-prepare-nodes.sh
```
*   **功能**: 分发 Kubernetes 二进制文件 (kubelet, kubeadm, kubectl, containerd 等) 和配置文件。
*   **机制**: 文件会从 `EXISTING_WORKER_IP` 下载到堡垒机，再上传到新节点 (中转模式)。

### 3. 加入集群
```bash
./03-join-cluster.sh
```
*   **功能**: 获取 Token，配置临时引导 Hosts，执行 `kubeadm join`，并启动本地 HAProxy。
*   **验证**: 执行完成后，请在 Master 上运行 `kubectl get nodes` 确认节点状态。

### 4. 同步 Hosts
```bash
./04-sync-hosts.sh
```
*   **功能**: 将新节点的信息同步更新到所有老节点的 `/etc/hosts` 中，确保集群内域名解析正常。

## 故障排查

*   **SSH 连接失败**: 检查 `config.sh` 中的 `SSH_IDENTITY_FILE` 路径是否正确，以及权限是否为 600。
*   **文件传输慢**: 脚本通过堡垒机中转文件，速度取决于堡垒机的网络带宽。
*   **Join 失败**: 检查新节点是否能 ping 通 Master IP，以及防火墙是否放行了 6443 端口。
