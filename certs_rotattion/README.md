# Kubernetes 集群 CA 证书轮换自动化工具

## 目录

1. [简介](https://www.google.com/url?sa=E&q=#1-%E7%AE%80%E4%BB%8B)
2. [设计原则](https://www.google.com/url?sa=E&q=#2-%E8%AE%BE%E8%AE%A1%E5%8E%9F%E5%88%99)
3. [准备工作](https://www.google.com/url?sa=E&q=#3-%E5%87%86%E5%A4%87%E5%B7%A5%E4%BD%9C)
   * [环境要求](https://www.google.com/url?sa=E&q=#%E7%8E%AF%E5%A2%83%E8%A6%81%E6%B1%82)
   * [配置 (00-config.sh)](https://www.google.com/url?sa=E&q=#%E9%85%8D%E7%BD%AE-00-configsh)
4. [执行流程 (重要)](https://www.google.com/url?sa=E&q=#4-%E6%89%A7%E8%A1%8C%E6%B5%81%E7%A8%8B-%E9%87%8D%E8%A6%81)
   * [第 0 步: 准备 (01-prepare.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-0-%E6%AD%A5-%E5%87%86%E5%A4%87-01-preparesh)
   * [第 1 步: 应用 Bundle 配置 (02-apply-bundle.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-1-%E6%AD%A5-%E5%BA%94%E7%94%A8-bundle-%E9%85%8D%E7%BD%AE-02-apply-bundlesh)
   * [第 2 步: 应用新叶子证书 (03-apply-new-certs.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-2-%E6%AD%A5-%E5%BA%94%E7%94%A8%E6%96%B0%E5%8F%B6%E5%AD%90%E8%AF%81%E4%B9%A6-03-apply-new-certssh)
   * [第 3 步: 应用最终配置 (04-apply-final-config.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-3-%E6%AD%A5-%E5%BA%94%E7%94%A8%E6%9C%80%E7%BB%88%E9%85%8D%E7%BD%AE-04-apply-final-configsh)
5. [安全保障与最佳实践](https://www.google.com/url?sa=E&q=#5-%E5%AE%89%E5%85%A8%E4%BF%9D%E9%9A%9C%E4%B8%8E%E6%9C%80%E4%BD%B3%E5%AE%9E%E8%B7%B5)
   * [零停机设计](https://www.google.com/url?sa=E&q=#%E9%9B%B6%E5%81%9C%E6%9C%BA%E8%AE%BE%E8%AE%A1)
   * [操作间隔建议](https://www.google.com/url?sa=E&q=#%E6%93%8D%E4%BD%9C%E9%97%B4%E9%9A%94%E5%BB%BA%E8%AE%AE)
   * [为业务应用配置 PDB](https://www.google.com/url?sa=E&q=#%E4%B8%BA%E4%B8%9A%E5%8A%A1%E5%BA%94%E7%94%A8%E9%85%8D%E7%BD%AE-pdb)
6. [灾难恢复 (回滚)](https://www.google.com/url?sa=E&q=#6-%E7%81%BE%E9%9A%BE%E6%81%A2%E5%A4%8D-%E5%9B%9E%E6%BB%9A)
7. [脚本清单](https://www.google.com/url?sa=E&q=#7-%E8%84%9A%E6%9C%AC%E6%B8%85%E5%8D%95)

---

## 1. 简介

**本工具集提供了一套完整的自动化脚本，用于安全、平滑地轮换现有 Kubernetes 集群的 CA (证书颁发机构) 证书。这包括 Kubernetes 核心组件 CA、Etcd CA 以及 Front-Proxy CA。**

**在不重新部署集群的情况下，证书过期是一个常见的运维痛点。本工具旨在通过自动化的方式，解决这一复杂问题，适用于通过 kubeadm 或类似二进制方式部署的、对线上业务连续性有高要求的生产环境。**

## 2. 设计原则

**本工具遵循以下核心原则，以确保操作的安全性和可靠性：**

* **零停机 (Zero Downtime)**: 整个轮换过程通过“信任扩展 -> 证书替换 -> 信任收缩”的三阶段方法，结合滚动更新策略，确保集群服务和业务应用零中断。
* **幂等性与可重复性**: 脚本设计力求幂等，多次执行同一阶段不会产生意外副作用。
* **自动化与智能化**: 自动发现节点信息，智能提取现有证书的 SANs (使用者可选名称)，最大限度减少手动配置和人为错误。
* **环境适应性**: 兼容 Master 与 Etcd 节点合并部署及分离部署两种主流架构。
* **可回滚性**: 提供了在紧急情况下一键回滚到初始状态的能力。
* **配置与逻辑分离**: 所有环境相关配置集中在 00-config.sh，方便用户适配不同集群。

## 3. 准备工作

**在执行任何操作之前，请务必完成以下准备工作。**

### 环境要求

1. **堡垒机**: 需要一台可以免密 SSH 登录到所有集群节点（Master, Worker, Etcd）的堡垒机。
2. **工具依赖**: 堡垒机和所有集群节点需要安装 rsync, openssl, ssh。堡垒机需要安装 kubectl 并配置好初始的管理权限。
3. **SSH 密钥**: 准备好用于登录所有节点的 SSH 密钥。
4. **集群拓扑**: 清晰了解你的集群拓扑，特别是 Master 节点和 Etcd 节点的 IP 列表。

### 配置 (00-config.sh)

**这是****唯一**需要你手动修改的文件。请根据你的集群环境，仔细填写以下配置。

**codeBash**

```
#!/bin/bash

# --- 工作区配置 ---
# 所有生成的文件将存放在堡垒机的这个目录下
WORKSPACE_DIR="/home/user/k8s-ca-rotation"

# --- 节点信息 ---
# 包含所有集群节点 IP 的文件，每行一个。
HOSTS_FILE="./hosts.info"

# !!! 关键配置: 明确指定 etcd 和 Master 节点 IP 列表
ETCD_NODES=("172.30.1.12" "172.30.1.14" "172.30.1.15")
MASTER_NODES=("172.30.1.12" "172.30.1.14" "172.30.1.15")

# --- 远程连接配置 ---
SSH_USER="root" # 确保此用户有权访问所有相关目录并重启服务
SSH_KEY="/path/to/your/ssh/private_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i ${SSH_KEY}"

# --- 远程路径配置 (!!! 关键配置，请务必核对) ---
REMOTE_K8S_CONFIG_DIR="/etc/kubernetes"
REMOTE_ETCD_SSL_DIR="/etc/ssl/etcd/ssl"
# [重要] kubelet.conf 的实际路径，请通过 `ps aux | grep kubelet` 查看 --kubeconfig 参数确认
REMOTE_KUBELET_CONF="/etc/kubernetes/kubelet.conf" 
REMOTE_ETCD_ENV_FILE="/etc/etcd.env" # 如果你的 Etcd 启动参数在该文件中定义
REMOTE_ETCDCTL_PATH="/usr/local/bin/etcdctl" # etcdctl 在远程节点上的绝对路径
ETCD_CLIENT_PORT="2379"

# --- 新证书配置 ---
CA_EXPIRY_DAYS=3650  # 新 CA 有效期 (天)
CERT_EXPIRY_DAYS=365 # 新叶子证书有效期 (天)

# 新 CA 的 Subject 信息
K8S_CA_SUBJECT="/CN=kubernetes"
ETCD_CA_SUBJECT="/CN=etcd-ca"
FRONT_PROXY_CA_SUBJECT="/CN=front-proxy-ca"
```

## 4. 执行流程 (重要)

**请严格按照以下顺序执行脚本，并在每个修改线上集群的步骤之间****留出充分的观察期**。

### 第 0 步: 准备 (01-prepare.sh)

* **作用**: 此脚本**不修改**线上集群。它在堡垒机的 ${WORKSPACE_DIR} 目录下完成所有准备工作。
* **执行内容**:
  1. **备份所有节点的现有证书和配置文件到各节点的 old/ 目录。**
  2. **生成全新的 K8s, Etcd, Front-Proxy CA。**
  3. **智能提取现有证书的 SANs，用于生成新证书。**
  4. **生成所有由新 CA 签发的叶子证书，存放于各节点的 new/ 目录。**
  5. **生成用于平滑过渡的“混合 CA” (bundle) 配置，存放于各节点的 bundle/ 目录。**
* **执行命令**: ./01-prepare.sh

### 第 1 步: 应用 Bundle 配置 (02-apply-bundle.sh)

* **目标**: 建立双 CA 信任 (Trust Expansion)。
* **执行内容**:
  1. **将所有节点的 CA 证书和相关 .conf 文件替换为 bundle/ 目录下的“混合 CA”版本。**
  2. **采用滚动更新方式，逐个重启节点上的 kubelet 来应用变更。**
  3. **每次重启后，都会检查节点状态和 Etcd 集群健康，确保集群稳定。**
* **执行命令**: ./02-apply-bundle.sh
* **完成后状态**: 集群所有组件同时信任新旧两个 CA，但仍在使用旧的叶子证书。**集群服务无中断**。

### 第 2 步: 应用新叶子证书 (03-apply-new-certs.sh)

* **目标**: 更换所有组件的身份凭证 (Certificate Rotation)。
* **执行内容**:
  1. **将所有控制平面节点的叶子证书替换为 new/ 目录下的、由新 CA 签发的新证书。**
  2. **注意**: 此步骤**不修改** CA 证书，信任根依然是“混合 CA”。
  3. **同样采用滚动更新和健康检查。**
* **执行命令**: ./03-apply-new-certs.sh
* **完成后状态**: 集群所有组件都已使用新证书进行通信，但信任根依然是双向信任。**集群服务无中断**。

### 第 3 步: 应用最终配置 (04-apply-final-config.sh)

* **目标**: 移除对旧 CA 的信任 (Trust Contraction)。
* **执行内容**:
  1. **将所有节点的 CA 证书和 .conf 文件替换为 new/ 目录下的、只包含新 CA 的最终版本。**
  2. **滚动更新并进行健康检查。**
* **执行命令**: ./04-apply-final-config.sh
* **完成后状态**: 集群完全迁移到新的 CA 体系下，旧 CA 被彻底移除。**CA 轮换成功，集群服务无中断**。

## 5. 安全保障与最佳实践

### 零停机设计

**本工具通过两大核心机制保障服务连续性：**

1. **信任扩展/收缩模型**: 确保在变更的任何阶段，新旧证书都能被集群正确验证。
2. **滚动更新与健康检查**: 逐个节点进行变更，并在每一步后确认节点和核心服务（如 Etcd）的健康，防止连锁故障。

### 操作间隔建议

**为了最大限度保障生产环境的稳定性，****强烈建议**在每个修改集群的步骤之间留出充分的观察期。

| **阶段**               | **建议观察时长**    | **观察重点**                                                 |
| ---------------------------- | ------------------------- | ------------------------------------------------------------------ |
| **02-apply-bundle**    | **30分钟 ~ 数小时** | **kube-system Pods 状态, kubectl get nodes, 监控指标无异常** |
| **03-apply-new-certs** | **半天 ~ 一天**     | **(同上)**，并重点关注新建 Pod 功能、业务应用日志            |
| **04-apply-final**     | **30分钟 ~ 1小时**  | **最后一次确认集群在新 CA 体系下完全正常**                   |

**不要着急！充分的观察是成功变更的关键。**

### 为业务应用配置 PDB

**为了防止滚动更新（kubelet 重启）期间业务应用发生中断，建议为所有关键应用（特别是多副本的 Deployment 和 StatefulSet）配置 ****PodDisruptionBudget (PDB)**。

**PDB 可以确保在节点维护期间，应用的可用副本数不会低于你设定的阈值。**

**示例 (my-app-pdb.yaml)**:

**codeYaml**

```
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2  # 保证 my-app 至少有2个副本可用
  selector:
    matchLabels:
      app: my-app # 必须与你的应用 Pod 标签匹配
```

**在执行 02-apply-bundle.sh ****之前**，通过 kubectl apply -f 应用所有 PDB 配置。

## 6. 灾难恢复 (回滚)

**如果在 02, 03, 04 任何一步执行后，集群出现严重故障且无法快速修复，可以使用 rollback.sh 脚本进行紧急回滚。**

* **作用**: 将**所有节点**的配置恢复到执行 01-prepare.sh 之前的初始状态。
* **执行内容**:
  1. **从 ${WORKSPACE_DIR} 中各节点的 old/ 目录读取原始备份。**
  2. **将这些备份文件并行地同步回所有对应的节点。**
  3. **重启所有节点上的 kubelet。**
* **执行命令**: ./rollback.sh
* **警告**: 这是一个全局性的、有损的快速恢复操作，仅在万不得已时使用。执行后请手动检查集群状态。

## 7. 脚本清单

* **00-config.sh: 环境变量配置文件。**
* **lib.sh: 包含所有公共函数的库脚本。**
* **01-prepare.sh: 准备阶段脚本。**
* **02-apply-bundle.sh: 应用混合 CA 脚本。**
* **03-apply-new-certs.sh: 应用新叶子证书脚本。**
* **04-apply-final-config.sh: 应用最终配置脚本。**
* **rollback.sh: 紧急回滚脚本。**
* **hosts.info: 集群所有节点 IP 列表文件。**
