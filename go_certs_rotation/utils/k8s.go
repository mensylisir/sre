package utils

import (
	"context"
	"fmt"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

// WaitForNodeReady waits for a Kubernetes node to be in the 'Ready' state.
func WaitForNodeReady(kubeconfigPath, nodeName string, timeout time.Duration) error {
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	if err != nil {
		return fmt.Errorf("failed to build kubeconfig: %w", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return fmt.Errorf("failed to create kubernetes clientset: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("timeout waiting for node %s to be ready", nodeName)
		case <-ticker.C:
			node, err := clientset.CoreV1().Nodes().Get(context.TODO(), nodeName, metav1.GetOptions{})
			if err != nil {
				InfoLogger.Printf("Failed to get node %s: %v", nodeName, err)
				continue
			}

			for _, condition := range node.Status.Conditions {
				if condition.Type == "Ready" && condition.Status == "True" {
					InfoLogger.Printf("Node %s is ready.", nodeName)
					return nil
				}
			}
			InfoLogger.Printf("Node %s is not ready yet.", nodeName)
		}
	}
}
