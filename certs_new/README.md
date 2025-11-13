# Kubernetes 全新证书签发自动化工具

## 目录

1. [简介](https://www.google.com/url?sa=E&q=#1-%E7%AE%80%E4%BB%8B)
2. [设计原则](https://www.google.com/url?sa=E&q=#2-%E8%AE%BE%E8%AE%A1%E5%8E%9F%E5%88%99)
3. [准备工作](https://www.google.com/url?sa=E&q=#3-%E5%87%86%E5%A4%87%E5%B7%A5%E4%BD%9C)
   * [环境要求](https://www.google.com/url?sa=E&q=#%E7%8E%AF%E5%A2%83%E8%A6%81%E6%B1%82)
   * [配置 (00-config-sign.sh)](https://www.google.com/url?sa=E&q=#%E9%85%8D%E7%BD%AE-00-config-signsh)
4. [完整执行流程 (重要)](https://www.google.com/url?sa=E&q=#4-%E5%AE%8C%E6%95%B4%E6%89%A7%E8%A1%8C%E6%B5%81%E7%A8%8B-%E9%87%8D%E8%A6%81)
   * [第 1 步: 生成证书 (01-generate-all-certs.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-1-%E6%AD%A5-%E7%94%9F%E6%88%90%E8%AF%81%E4%B9%A6-01-generate-all-certssh)
   * [第 2 步: 生成 Kubeconfig (02-generate-kubeconfigs.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-2-%E6%AD%A5-%E7%94%9F%E6%88%90-kubeconfig-02-generate-kubeconfigssh)
   * [第 3 步: 分发文件 (03-deploy-certs.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-3-%E6%AD%A5-%E5%88%86%E5%8F%91%E6%96%87%E4%BB%B6-03-deploy-certssh)
   * [第 4 步: 启动服务 (04-start-services.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-4-%E6%AD%A5-%E5%90%AF%E5%8A%A8%E6%9C%8D%E5%8A%A1-04-start-servicessh)
   * [第 5 步: 验证集群 (05-validate-cluster.sh)](https://www.google.com/url?sa=E&q=#%E7%AC%AC-5-%E6%AD%A5-%E9%AA%8C%E8%AF%81%E9%9B%86%E7%BE%A4-05-validate-clustersh)
5. [灾难恢复 (回滚)](https://www.google.com/url?sa=E&q=#5-%E7%81%BE%E9%9A%BE%E6%81%A2%E5%A4%8D-%E5%9B%9E%E6%BB%9A)
6. [脚本清单](https://www.google.com/url?sa=E&q=#6-%E8%84%9A%E6%9C%AC%E6%B8%85%E5%8D%95)

---

## 1. 简介

**本工具集提供了一套完整的自动化脚本，用于****从零开始**为全新的 Kubernetes 集群签发所有必需的 CA、证书、密钥以及 kubeconfig 配置文件。它特别适用于进行**二进制部署**或需要使用**外部 CA** 的 kubeadm 高级部署场景。

**与“证书轮换”不同，本工具的目标是创建一个全新的 PKI (公钥基础设施) 体系，并将其部署到集群节点，为启动一个全新的、安全的 Kubernetes 集群做好所有凭证准备。**

## 2. 设计原则

* **配置驱动**: 所有环境特定的信息（如节点 IP、SANs、服务器地址）都集中在 00-config-sign.sh 中，易于配置和管理。
* **自动化与智能化**: 自动发现节点主机名，并根据节点角色动态构建符合生产环境最佳实践的 SANs 列表，最大限度减少手动配置。
* **架构通用性**: 完美支持 Master 与 Etcd 节点合并部署及分离部署两种架构。
* **结构化输出**: 生成的文件按节点和组件清晰地组织，方便审查和部署。
* **端到端流程**: 提供从证书生成、配置组装、文件分发、服务启动到最终验证的完整端到端自动化流程。
* **安全性**: 在部署高风险操作前提供确认机制，并具备回滚能力。

## 3. 准备工作

**在执行任何操作之前，请务必完成以下准备工作。**

### 环境要求

1. **堡垒机**: 需要一台可以免密 SSH 登录到所有目标集群节点（Master, Worker, Etcd）的堡垒机。
2. **工具依赖**: 堡垒机和所有集群节点需要安装 rsync, openssl, ssh。
3. **SSH 密钥**: 准备好用于登录所有节点的 SSH 密钥。
4. **集群拓扑**: 清晰规划你的新集群拓扑，特别是 Master 节点和 Etcd 节点的 IP 列表。

### 配置 (00-config-sign.sh)

**这是****唯一**需要你手动修改的文件。请根据你的新集群规划，仔细填写以下配置。

**codeBash**

```
#!/bin/bash

# --- 工作区配置 ---
WORKSPACE_DIR="./k8s-new-certs"

# --- 节点信息 ---
HOSTS_FILE="./hosts.info" # 包含新集群所有节点 IP 的文件，每行一个

# !!! 关键配置: 明确指定 etcd 和 Master 节点 IP 列表
ETCD_NODES_IP=("172.30.1.12" "172.30.1.14" "172.30.1.15")
MASTER_NODES_IP=("172.30.1.12" "172.30.1.14" "172.30.1.15")

# --- SSH 配置 ---
SSH_USER="root"
SSH_KEY="/path/to/your/ssh/private_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY}"

# --- 证书配置 ---
CA_EXPIRY_DAYS=3650
CERT_EXPIRY_DAYS=365

# CA 的 Subject 信息
K8S_CA_SUBJECT="/CN=kubernetes"
ETCD_CA_SUBJECT="/CN=etcd-ca"
FRONT_PROXY_CA_SUBJECT="/CN=front-proxy-ca"

# --- 额外 SANs (可选) ---
# 脚本会自动生成节点相关的 SANs，这里只需填写额外的地址
# 例如负载均衡器、特殊的 Service IP (apiserver 的 IP 通常是 service-cidr 的第一个 IP)
K8S_APISERVER_EXTRA_SANS="DNS:lb.example.com,IP:10.96.0.1"
ETCD_EXTRA_SANS="DNS:etcd.example.com,DNS:localhost,IP:127.0.0.1"

# !!! 关键配置: APIServer 连接配置 !!!
# 用于生成所有 kubeconfig 文件的服务器地址。
# 强烈建议使用高可用地址 (如负载均衡器的 VIP 或 DNS 名称)。
CLUSTER_APISERVER_URL="https://lb.example.com:6443"
CLUSTER_NAME="kubernetes"

# --- 远程路径配置 (部署时使用) ---
REMOTE_K8S_DIR="/etc/kubernetes"
REMOTE_ETCD_DIR="/etc/ssl/etcd/ssl"
REMOTE_ETCDCTL_PATH="/usr/local/bin/etcdctl"
ETCD_CLIENT_PORT="2379"
```

## 4. 完整执行流程 (重要)

**请严格按照以下顺序执行脚本。**

### 第 1 步: 生成证书 (01-generate-all-certs.sh)

* **作用**: 在堡垒机上生成部署一个完整集群所需的所有 CA、证书和密钥。
* **执行内容**:
  1. **动态获取所有节点的主机名。**
  2. **根据节点角色（Master, Etcd, Worker）自动构建符合你环境的“大而全”SANs 列表。**
  3. **生成 K8s, Etcd, Front-Proxy 三大根 CA。**
  4. **为每个节点生成其角色所需的全部叶子证书（如 apiserver.crt, etcd-member.pem, kubelet.crt 等）。**
* **执行命令**: ./01-generate-all-certs.sh

### 第 2 步: 生成 Kubeconfig (02-generate-kubeconfigs.sh)

* **作用**: 利用上一步生成的证书，组装所有组件所需的 kubeconfig 配置文件。
* **执行内容**:
  1. **为所有节点生成 kubelet.conf。**
  2. **为所有 Master 节点生成 admin.conf, controller-manager.conf, scheduler.conf。**
  3. **(如果需要) 为 kube-proxy 生成 kube-proxy.conf。**
* **执行命令**: ./02-generate-kubeconfigs.sh

### 第 3 步: 分发文件 (03-deploy-certs.sh)

* **作用**: 将堡垒机上生成的所有文件安全地部署到新集群的每个节点上。
* **执行内容**:
  1. **备份**: 在分发前，会自动备份目标节点上可能存在的旧配置目录（如 /etc/kubernetes -> /etc/kubernetes.bak.xxxx）。
  2. **分发**: 将每个节点对应的证书和配置文件 rsync 到远程节点的正确路径下。
  3. **权限设置**: 自动为所有私钥文件设置安全的 600 权限。
* **执行命令**: ./03-deploy-certs.sh

### 第 4 步: 启动服务 (04-start-services.sh)

* **作用**: 自动化地、按正确顺序启动（或重启）所有集群服务。
* **执行内容**:
  1. **滚动重启所有 Etcd 节点上的 etcd 服务。**
  2. **在所有 Etcd 节点重启后，对整个 Etcd 集群进行一次最终的健康检查。**
  3. **滚动重启所有节点上的 kubelet 和 kube-proxy 服务（这将自动启动作为静态 Pod 的控制平面组件）。**
  4. **等待并确认所有 Kubernetes 节点都成功加入集群并处于 Ready 状态。**
* **执行命令**: ./04-start-services.sh

### 第 5 步: 验证集群 (05-validate-cluster.sh)

* **作用**: 提供一个标准化的“体检”流程，深度验证集群的核心功能是否正常。
* **执行内容**:
  1. **检查节点状态、组件健康状态、核心 Pod 状态。**
  2. **通过部署一个临时 Pod 来****验证集群 DNS 解析**是否正常工作。
  3. **通过部署一个 Nginx 服务并从另一个 Pod 访问它，来****验证 Service 和 Pod 间网络**是否通畅。
* **执行命令**: ./05-validate-cluster.sh

## 5. 灾难恢复 (回滚)

**如果在****部署 (03)** 或**启动 (04)** 阶段遇到严重问题，可以使用 rollback-deploy.sh 脚本进行紧急回滚。

* **作用**: 将所有被修改过的节点的配置，恢复到执行 03-deploy-certs.sh 之前的状态。
* **执行内容**:
  1. **在每个节点上查找最新的备份目录（.bak.xxxx）。**
  2. **用最新的备份目录覆盖当前配置。**
  3. **重启相关服务。**
* **执行命令**: ./rollback-deploy.sh
* **警告**: 这是一个全局性的恢复操作，仅在紧急情况下使用。

## 6. 脚本清单

* **00-config-sign.sh: 环境变量配置文件。**
* **lib-sign.sh: 包含所有公共函数的库脚本。**
* **01-generate-all-certs.sh: ****生成**证书和密钥。
* **02-generate-kubeconfigs.sh: ****组装** kubeconfig 文件。
* **03-deploy-certs.sh: ****分发**所有生成的文件。
* **04-start-services.sh: ****启动/重启**集群服务。
* **05-validate-cluster.sh: ****验证**集群核心功能。
* **rollback-deploy.sh: 紧急****回滚**部署操作。
* **hosts.info: 集群所有节点 IP 列表文件。**
