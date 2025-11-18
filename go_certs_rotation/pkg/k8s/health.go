package k8s

import (
	"context"
	"fmt"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// WaitForNodeReady waits for a Kubernetes node to report a 'Ready' status.
func WaitForNodeReady(clientset *kubernetes.Clientset, nodeName string, timeout time.Duration) error {
	fmt.Printf("Waiting for node %s to become Ready...\n", nodeName)
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("timeout expired waiting for node %s to be ready", nodeName)
		case <-ticker.C:
			node, err := clientset.CoreV1().Nodes().Get(context.TODO(), nodeName, metav1.GetOptions{})
			if err != nil {
				fmt.Printf("  - Failed to get node %s: %v\n", nodeName, err)
				continue
			}

			for _, condition := range node.Status.Conditions {
				if condition.Type == "Ready" {
					if condition.Status == "True" {
						fmt.Printf("  - Node %s is Ready.\n", nodeName)
						return nil
					}
					fmt.Printf("  - Node %s is not Ready yet (Reason: %s, Message: %s)\n", nodeName, condition.Reason, condition.Message)
				}
			}
		}
	}
}
