# K8s 集群 CA 证书轮换脚本 - 详细流程说明

本文档详细解释了 `certs` 目录中各脚本的执行逻辑，旨在为审查和理解证书轮换流程提供清晰、具体的操作步骤。

## 核心逻辑

轮换遵循“**准备 -> 建立双信任 -> 替换叶子证书 -> 清理旧信任**”的最佳实践，以确保在任何阶段都不会中断集群服务。

---

### `00-config.sh` & `lib.sh` - 基础配置与工具库

*   **`00-config.sh`**: **配置中心**。在执行任何操作前，必须在此文件中正确配置所有变量，包括：
    *   `WORKSPACE_DIR`: 本地工作目录，所有生成的文件和备份都将存放于此。
    *   `HOSTS_FILE`: 包含所有集群节点IP的列表文件。
    *   `ETCD_NODES`, `MASTER_NODES`: 明确指定 Etcd 和 Master 节点的 IP。
    *   `SSH_USER`, `SSH_KEY`: 用于远程连接的 SSH 用户和密钥。
    *   `REMOTE_*_DIR`: 远程节点上 Kubernetes 和 Etcd 的相关目录路径。
*   **`lib.sh`**: **工具函数库**。封装了所有脚本都会用到的核心操作，例如：
    *   `run_remote`: 通过 `ssh` 在远程节点上执行命令。
    *   `sync_to_remote`/`sync_from_remote`: 通过 `rsync` 与远程节点同步或拉取文件。
    *   `generate_ca`/`generate_leaf_cert`: 通过 `openssl` 命令生成 CA 和叶子证书。
    *   `wait_for_node_ready`: 通过 `kubectl get node` 检查并等待节点恢复 `Ready` 状态。
    *   `update_kubeconfig_ca`: 通过 `sed` 命令更新 kubeconfig 文件中的 `certificate-authority-data` 字段。

---

### `01-prepare.sh` - 准备阶段 (本地操作)

**目标**: 在不接触线上集群配置的情况下，在本地准备好所有需要的文件，包括备份、新证书和过渡配置。

*   **步骤 1: 初始化并拉取备份**
    *   **动作**: 连接到 `HOSTS_FILE` 中的每个节点，执行 `hostname -s` 获取其主机名。
    *   **动作**: 使用 `rsync` 从每个远程节点拉取 `/etc/kubernetes`、`/etc/ssl/etcd/ssl` 和 `/var/lib/kubelet/kubelet.conf` 等关键配置文件。
    *   **结果**: 在本地工作区为每个节点创建了 `<hostname>/old/` 目录，其中包含了线上配置的完整备份。

*   **步骤 2: 生成新 CA 和叶子证书**
    *   **动作**: 使用 `openssl req -x509` 命令生成一套全新的 CA 证书（k8s-ca, etcd-ca, front-proxy-ca），存放于 `new-cas/` 目录。
    *   **动作**: **智能提取 SANs**: 通过 `openssl x509 -noout -text` 读取**第一个 Master 节点**的旧 `apiserver.crt` 证书，从中提取出所有的主备用名称 (Subject Alternative Names)。这是**关键一步**，确保了新的 apiserver 证书包含了所有必需的 IP 和域名。
    *   **动作**: 使用 `generate_leaf_cert` 函数，为每个节点签发一套全新的叶子证书（apiserver, etcd-member, admin 等）。
*   **动作**: **关键修复**: 复制旧的 `kubelet.conf` 和 `admin.conf` 等文件到 `<hostname>/new/` 目录后，**立即调用 `update_kubeconfig_ca` 函数**，将其中的 `certificate-authority-data` 字段更新为**新 CA** 的 Base64 内容。
*   **结果**: 在本地工作区为每个节点创建了 `<hostname>/new/` 目录。此目录下的所有配置文件都已正确配置为**仅信任新 CA**，所有证书也都由新 CA 签发。

*   **步骤 3: 创建“双信任”过渡配置**
    *   **动作**: 使用 `cat old-ca.crt new-ca.crt > k8s-bundle.crt` 的方式，将旧 CA 和新 CA 的内容合并成一个临时的“CA bundle”文件。
    *   **动作**: 复制 `<hostname>/old/` 目录为 `<hostname>/bundle/`。
    *   **动作**: 针对 `bundle` 目录中的所有 kubeconfig 文件 (`admin.conf`, `kubelet.conf` 等)，调用 `update_kubeconfig_ca` 函数，使用 `sed` 将其 CA 数据替换为 “CA bundle” 的 Base64 编码。同时，将 `ca.crt` 文件也替换为 “CA bundle” 文件本身。
    *   **结果**: `<hostname>/bundle/` 目录包含了一套能同时信任新旧两个 CA 的过渡时期配置。

---

### `02-apply-bundle.sh` - 应用过渡配置 (建立双信任)

**目标**: 将“双信任”配置应用到集群，使所有组件都能验证新旧两种证书。

*   **步骤 1: 滚动更新 Worker 节点**
    *   **动作**: 遍历所有 Worker 节点，将 `<hostname>/bundle/kubelet.conf` 同步到远程节点的 `/var/lib/kubelet/` 目录下。
    *   **动作**: 执行 `systemctl restart kubelet` 重启服务。
    *   **动作**: 调用 `wait_for_node_ready` 确保节点恢复正常。

*   **步骤 2: 滚动更新 Master 节点**
    *   **动作**: 遍历所有 Master 节点，将 `<hostname>/bundle/` 下的 `kubernetes` 和 `etcd-ssl` 目录完整同步到远程节点。同时更新 `kubelet.conf`。
    *   **动作**: 执行 `systemctl restart kubelet`。这会触发由 kubelet 管理的静态 Pod (apiserver, scheduler, etcd 等) 重启，并加载新的“双信任”CA。
    *   **动作**: 等待节点恢复 Ready。

---

### `03-apply-new-certs.sh` - 更换叶子证书

**目标**: 在集群已建立双信任的基础上，安全地将所有组件的证书替换为新证书。

*   **动作**: **仅遍历 Master 节点**。
*   **动作**: 使用 `rsync` 将 `<hostname>/new/` 目录下的 **Kubernetes 叶子证书**同步到远程 Master 节点。**关键操作**: 使用 `--exclude='ca.crt' --exclude='ca.key'` 等参数，**跳过 CA 文件**，确保“双信任”状态不被破坏。
*   **动作**: 将新的 **Etcd 叶子证书**同步到远程 Etcd 节点。
*   **动作**: 重启 `kubelet`，使 apiserver, etcd 等服务加载并开始使用由新 CA 签发的新证书对外提供服务。

---

### `04-apply-final-config.sh` - 应用最终配置 (完成切换)

**目标**: 移除对旧 CA 的信任，完成整个轮换流程。

*   **步骤 1: 滚动更新 Worker 节点**
    *   **动作**: 将 `<hostname>/new/kubelet.conf` (此文件仅包含新 CA) 同步到远程 Worker 节点并重启 kubelet。

*   **步骤 2: 滚动更新 Master 节点**
    *   **动作**: 将 `<hostname>/new/` 目录下的**所有文件**（包括新的 `ca.crt`, `ca.key` 和 `admin.conf` 等）完整同步到远程 Master 节点，彻底覆盖掉之前的“bundle”配置。
    *   **动作**: 重启 `kubelet`。静态 Pod 将加载最终配置，集群完全切换到新的证书体系。

---

### `rollback.sh` - 灾难回滚

**目标**: 在任何步骤发生严重问题时，快速将集群恢复到操作前的状态。

*   **动作**: **并行处理**所有节点以缩短恢复时间。
*   **动作**: 将 `<hostname>/old/` 目录（即 `01-prepare.sh` 步骤中创建的初始备份）的内容强制同步回所有对应的远程节点。
*   **动作**: 重启所有节点的 `kubelet` 服务，使集群恢复到初始配置。
