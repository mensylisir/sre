#!/bin/bash

# 获取所有命名空间，排除系统自带和状态异常的
NAMESPACES=$(kubectl get ns -o jsonpath='{.items[?(@.status.phase=="Active")].metadata.name}' | grep -vE '^(kube-system|kube-public|kube-node-lease)$')

for ns in $NAMESPACES; do
  echo "--- Restarting workloads in namespace: $ns ---"

  # 重启 Deployments
  kubectl get deployment -n "$ns" -o name | xargs -r -I {} kubectl rollout restart {} -n "$ns"

  # 重启 StatefulSets
  kubectl get statefulset -n "$ns" -o name | xargs -r -I {} kubectl rollout restart {} -n "$ns"

  # 重启 DaemonSets
  kubectl get daemonset -n "$ns" -o name | xargs -r -I {} kubectl rollout restart {} -n "$ns"

  echo " "
done

echo "--- Restarting workloads in kube-system namespace ---"
# 单独处理 kube-system, 因为它很重要
kubectl get deployment -n kube-system -o name | xargs -r -I {} kubectl rollout restart {} -n kube-system
kubectl get statefulset -n kube-system -o name | xargs -r -I {} kubectl rollout restart {} -n kube-system
kubectl get daemonset -n kube-system -o name | xargs -r -I {} kubectl rollout restart {} -n kube-system


echo "All workload rollouts have been initiated."