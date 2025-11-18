package discovery

import (
	"context"
	"fmt"
	"go_certs_rotation/pkg/k8s"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// Cluster Topology holds the discovered topology of the Kubernetes cluster.
type ClusterTopology struct {
	MasterNodes []Node
	EtcdNodes   []Node
}

// Node represents a node in the cluster.
type Node struct {
	Name     string
	InternalIP string
}

// DiscoverTopology discovers the master and etcd nodes in the cluster.
func DiscoverTopology(clientset *kubernetes.Clientset) (*ClusterTopology, error) {
	topology := &ClusterTopology{}

	// Discover master nodes
	masterNodes, err := clientset.CoreV1().Nodes().List(context.TODO(), metav1.ListOptions{
		LabelSelector: "node-role.kubernetes.io/control-plane",
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list master nodes: %w", err)
	}

	for _, node := range masterNodes.Items {
		internalIP := ""
		for _, addr := range node.Status.Addresses {
			if addr.Type == "InternalIP" {
				internalIP = addr.Address
				break
			}
		}
		topology.MasterNodes = append(topology.MasterNodes, Node{Name: node.Name, InternalIP: internalIP})
	}

	// Discover etcd nodes (by looking at etcd pods in kube-system)
	etcdPods, err := clientset.CoreV1().Pods("kube-system").List(context.TODO(), metav1.ListOptions{
		LabelSelector: "component=etcd",
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list etcd pods: %w", err)
	}

    etcdNodeNames := make(map[string]bool)
	for _, pod := range etcdPods.Items {
		etcdNodeNames[pod.Spec.NodeName] = true
	}

    for _, node := range topology.MasterNodes {
        if etcdNodeNames[node.Name] {
            topology.EtcdNodes = append(topology.EtcdNodes, node)
        }
    }

	return topology, nil
}
