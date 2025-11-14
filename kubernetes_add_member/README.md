# Kubernetes 节点批量操作工具集

## 1. 概述

本项目是一套用于**批量**、**分步**操作 Kubernetes 新增节点的运维工具集。所有操作均在**总控机**上发起，由操作者完全控制执行节奏。

其核心设计思想是 **“配置与操作分离”**:

1. **`nodes.conf`**: 一个中央配置文件，您在这里定义**所有**将要被操作的目标节点（无论是 Master 还是 Worker）。
2. **任务脚本 (`01-*.sh`, `02-*.sh` ...)**: 每个脚本代表一个独立的操作步骤。当您执行一个任务脚本时，它会自动读取 `nodes.conf`，并将该操作应用到**所有**已定义的目标节点上。

这种模式赋予了操作者极大的灵活性和控制力，您可以清晰地观察每一步批量操作对所有节点产生的影响。

## 2. 操作流程

### 步骤一：定义目标

1. 打开 `nodes.conf` 文件。
2. 在 `ALL_NODES` 数组中，填入所有您这次希望添加的节点的 **IP、角色 (master/worker) 和 SSH 用户**。

### 步骤二：分步执行任务

在总控机上，**按数字顺序，逐一执行**以下任务脚本。

1. **初始化所有节点的操作系统**
   ```bash
   ./01-prepare-os.sh
   ```
2. **为所有节点安装依赖和二进制文件**
   ```bash
   ./02-install-dependencies.sh
   ```
3. **为所有节点配置并启动 containerd**
   ```bash
   ./03-setup-containerd.sh
   ```
4. **为所有节点配置 kubelet 服务 (不启动)**
   ```bash
   ./04-setup-kubelet.sh
   ```
5. **让所有节点加入集群 (脚本会自动区分 master 和 worker)**
   ```bash
   ./05-join-nodes.sh
   ```
6. **在所有新 worker 节点上部署 HAProxy**
   ```bash
   ./06-setup-haproxy.sh
   ```

### 步骤三：更新现有 Worker 的 HAProxy (仅在添加 Master 后需要)

如果您本次操作中添加了新的 Master 节点，则需要执行此步骤来更新集群中**原有** Worker 节点的负载均衡配置。

```bash
./07-update-worker-haproxy.sh
```
