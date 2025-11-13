# Kubernetes 集群证书体系一键替换工具

## 目录

1. [**警告：高风险操作**](https://www.google.com/url?sa=E&q=#1-%E8%AD%A6%E5%91%8A%E9%AB%98%E9%A3%8E%E9%99%A9%E6%93%8D%E4%BD%9C)
2. [简介](https://www.google.com/url?sa=E&q=#2-%E7%AE%80%E4%BB%8B)
3. [设计原则](https://www.google.com/url?sa=E&q=#3-%E8%AE%BE%E8%AE%A1%E5%8E%9F%E5%88%99)
4. [准备工作 (至关重要)](https://www.google.com/url?sa=E&q=#4-%E5%87%86%E5%A4%87%E5%B7%A5%E4%BD%9C-%E8%87%B3%E5%85%B3%E9%87%8D%E8%A6%81)
   * [环境要求](https://www.google.com/url?sa=E&q=#%E7%8E%AF%E5%A2%83%E8%A6%81%E6%B1%82)
   * [配置 (00-config-replace.sh)](https://www.google.com/url?sa=E&q=#%E9%85%8D%E7%BD%AE-00-config-replacesh)
5. [执行流程](https://www.google.com/url?sa=E&q=#5-%E6%89%A7%E8%A1%8C%E6%B5%81%E7%A8%8B)
   * [核心脚本 (replace-all-certs.sh)](https://www.google.com/url?sa=E&q=#%E6%A0%B8%E5%BF%83%E8%84%9A%E6%9C%AC-replace-all-certssh)
   * [执行步骤](https://www.google.com/url?sa=E&q=#%E6%89%A7%E8%A1%8C%E6%AD%A5%E9%AA%A4)
6. [灾难恢复 (回滚)](https://www.google.com/url?sa=E&q=#6-%E7%81%BE%E9%9A%BE%E6%81%A2%E5%A4%8D-%E5%9B%9E%E6%BB%9A)
7. [脚本清单](https://www.google.com/url?sa=E&q=#7-%E8%84%9A%E6%9C%AC%E6%B8%85%E5%8D%95)

---

## 1. 警告：高风险操作

**在继续之前，请务必阅读并理解以下内容：**

* **服务中断**: 本工具集执行的是**全量证书替换**，包括所有 CA（信任根）。这将导致集群中**所有核心组件（Etcd, APIServer, Kubelet 等）被强制重启**。此过程会造成一个**明确的、可感知的服务中断窗口**，时长取决于你的集群规模和节点性能。
* **数据风险**: 尽管脚本包含备份机制，但在一个正在运行的服务（尤其是 Etcd）上进行文件替换和重启，始终存在极小的**数据损坏或丢失风险**。强烈建议在执行此操作前，对 Etcd 和其他关键数据进行**完整备份**。
* **不可逆性**: 一旦操作成功，集群将完全迁移到新的证书体系下。回滚操作虽然可用，但仅用于灾难恢复，不能保证 100% 恢复所有状态。
* **适用场景**: 本工具适用于**计划内的、可接受停机窗口的**重大维护，或在测试/开发环境中重建证书体系。**请勿在业务高峰期对生产环境执行此操作。**

---

## 2. 简介

**本工具集提供了一个“一键式”的解决方案，用于对一个****正在运行的** Kubernetes 集群进行彻底的证书体系替换。它会生成一套全新的 CA 和叶子证书，并将其强制部署到集群的所有节点上，以替换现有的所有凭证。

**此工具的核心价值在于，它能够在保留现有集群配置和数据（如应用、网络策略等）的前提下，为集群“换一把全新的锁”。**

## 3. 设计原则

* **一键式操作**: 将证书的“准备、提取、生成、分发、重启”等所有步骤都整合到一个主脚本中，简化操作。
* **智能克隆**: 通过智能提取现有证书的 SANs 列表，确保新生成的证书能够 100% 匹配你现有的、可能非标准的集群网络配置。
* **安全优先的流程**: 采用**“停-换-启” (Stop-Replace-Start)** 的服务管理模式，在替换文件前先停止相关服务，从根本上杜绝竞态条件和文件覆盖风险。
* **架构通用性**: 能够正确处理 Master 与 Etcd 节点合并部署及分离部署两种架构。
* **备份与回滚**: 在执行覆盖操作前，自动备份远程节点上的关键配置目录，并提供回滚脚本用于紧急情况。

## 4. 准备工作 (至关重要)

### 环境要求

1. **堡垒机**: 一台可以免密 SSH 登录到所有集群节点的堡垒机。
2. **工具依赖**: 堡垒机和所有集群节点需安装 rsync, openssl, ssh。
3. **Etcd 备份**: **强烈建议**在执行脚本前，使用 etcdctl snapshot save 对 Etcd 数据进行一次完整快照备份。

### 配置 (00-config-replace.sh)

**这是****唯一**需要你手动修改的文件。请根据你的集群环境，仔细检查并填写每一项配置。

**codeBash**

```
#!/bin/bash

# --- 工作区配置 ---
WORKSPACE_DIR="./k8s-cert-replace"

# --- 节点信息 ---
HOSTS_FILE="./hosts.info" # 包含集群所有节点 IP 的文件

# !!! 关键配置: 明确指定 etcd 和 Master 节点 IP 列表
ETCD_NODES_IP=("172.30.1.12" "172.30.1.14" "172.30.1.15")
MASTER_NODES_IP=("172.30.1.12" "172.30.1.14" "172.30.1.15")

# --- SSH 配置 ---
SSH_USER="root"
SSH_KEY="/path/to/your/ssh/private_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY}"

# --- 新证书配置 ---
CA_EXPIRY_DAYS=3650
CERT_EXPIRY_DAYS=365
# ... (CA Subject 信息) ...

# !!! 关键配置: APIServer 连接配置 !!!
# 用于生成所有新 kubeconfig 文件的服务器地址。
CLUSTER_APISERVER_URL="https://lb.example.com:6443"
CLUSTER_NAME="kubernetes"

# --- 远程路径配置 (!!! 关键配置，请务必核对) ---
REMOTE_K8S_DIR="/etc/kubernetes"
REMOTE_ETCD_DIR="/etc/ssl/etcd/ssl"
REMOTE_KUBELET_CONF="/etc/kubernetes/kubelet.conf"
```

## 5. 执行流程

### 核心脚本 (replace-all-certs.sh)

**本工具集的核心是一个名为 replace-all-certs.sh 的主脚本，它会按顺序自动化执行所有步骤。**

* **步骤 1: 准备工作**: 在堡垒机上创建工作区，并从线上集群拉取少量旧证书样本，用于后续提取 SANs。
* **步骤 2: 提取 SANs**: 智能分析旧证书，精确提取 apiserver, etcd-member, etcd-admin, etcd-node 等证书的 SANs 列表。
* **步骤 3: 生成新文件**: 在堡垒机上生成一套全新的 CA、所有组件的叶子证书、以及所有需要的 kubeconfig 文件。
* **步骤 4: 备份、分发与重启**: 这是唯一接触线上集群的破坏性步骤。
  1. **停止服务**: 脚本会首先**停止**所有节点上的 kubelet, kube-proxy, etcd 服务。**（服务中断开始）**
  2. **备份与替换**: 脚本会在每个节点上备份现有的 /etc/kubernetes 和 /etc/ssl/etcd/ssl 目录，然后用全新的文件覆盖。
  3. **按序启动**: 脚本会**先启动所有 etcd 服务**，等待其稳定；然后**再启动所有 kubelet 和 kube-proxy 服务**。
* **步骤 5: 验证**: 脚本会等待所有节点重新加入集群并变为 Ready 状态，然后进行基础的健康检查。**（服务中断结束）**

### 执行步骤

1. **备份**: **手动执行 Etcd 快照备份！**
2. **配置**: 仔细填写 00-config-replace.sh 和 hosts.info 文件。
3. **授权**: chmod +x replace-all-certs.sh lib-replace.sh
4. **执行**:
   **codeBash**

   ```
   ./replace-all-certs.sh
   ```

   **脚本在第 3 步和第 4 步之间会要求你输入 yes 进行最终确认。请在确认前，确保你已了解所有风险并做好了准备。**

## 6. 灾难恢复 (回滚)

**如果在执行过程中脚本失败，或者重启后集群无法恢复，可以使用 rollback-deploy.sh 脚本进行紧急回滚。**

* **作用**: 将所有被修改过的节点的配置，恢复到执行 replace-all-certs.sh 之前的状态。
* **执行内容**:
  1. **在每个节点上查找最新的备份目录（.bak.xxxx）。**
  2. **用最新的备份目录覆盖当前配置。**
  3. **重启相关服务。**
* **执行命令**: ./rollback-deploy.sh
* **警告**: 这是一个全局性的恢复操作，仅在紧急情况下使用。

## 7. 脚本清单

* **00-config-replace.sh: 环境变量配置文件。**
* **lib-replace.sh: 包含所有公共函数的库脚本。**
* **replace-all-certs.sh: ****核心执行脚本**，一键完成所有操作。
* **rollback-deploy.sh: 紧急回滚脚本。**
* **hosts.info: 集群所有节点 IP 列表文件。**
