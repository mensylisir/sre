package discovery

import (
	"context"
	"fmt"
	"k8s.io/client-go/kubernetes"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Node represents a Kubernetes node with its name and internal IP address.
type Node struct {
	Name       string
	InternalIP string
}

// ClusterTopology holds the discovered lists of master and etcd nodes.
type ClusterTopology struct {
	MasterNodes []Node
	EtcdNodes   []Node
}

// DiscoverTopology connects to the Kubernetes API to discover the cluster topology.
func DiscoverTopology(clientset *kubernetes.Clientset) (*ClusterTopology, error) {
	fmt.Println("Discovering cluster topology...")
	topology := &ClusterTopology{}

	// Discover master nodes by label "node-role.kubernetes.io/control-plane"
	masterNodeList, err := clientset.CoreV1().Nodes().List(context.TODO(), metav1.ListOptions{
		LabelSelector: "node-role.kubernetes.io/control-plane",
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list master nodes: %w", err)
	}
	if len(masterNodeList.Items) == 0 {
		return nil, fmt.Errorf("no master nodes found with label 'node-role.kubernetes.io/control-plane'")
	}

	for _, node := range masterNodeList.Items {
		internalIP := ""
		for _, addr := range node.Status.Addresses {
			if addr.Type == "InternalIP" {
				internalIP = addr.Address
				break
			}
		}
		if internalIP == "" {
			return nil, fmt.Errorf("could not find internal IP for master node %s", node.Name)
		}
		topology.MasterNodes = append(topology.MasterNodes, Node{Name: node.Name, InternalIP: internalIP})
		fmt.Printf("  - Found master node: %s (%s)\n", node.Name, internalIP)
	}

	// Discover etcd nodes by checking which nodes host the etcd pods
	etcdPodList, err := clientset.CoreV1().Pods("kube-system").List(context.TODO(), metav1.ListOptions{
		LabelSelector: "component=etcd",
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list etcd pods: %w", err)
	}
	if len(etcdPodList.Items) == 0 {
		return nil, fmt.Errorf("no etcd pods found in 'kube-system' namespace with label 'component=etcd'")
	}

	etcdNodeNames := make(map[string]struct{})
	for _, pod := range etcdPodList.Items {
		etcdNodeNames[pod.Spec.NodeName] = struct{}{}
	}

	for _, node := range topology.MasterNodes {
		if _, ok := etcdNodeNames[node.Name]; ok {
			topology.EtcdNodes = append(topology.EtcdNodes, node)
			fmt.Printf("  - Found etcd node: %s (%s)\n", node.Name, node.InternalIP)
		}
	}

	if len(topology.EtcdNodes) == 0 {
		return nil, fmt.Errorf("could not associate any etcd pods with the discovered master nodes")
	}

	fmt.Println("Topology discovery complete.")
	return topology, nil
}
