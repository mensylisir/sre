package k8s

import (
	"fmt"
	"os"
	"path/filepath"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

// NewClientset creates a new Kubernetes clientset.
// If kubeconfigPath is empty, it attempts to find the configuration in the default
// location (~/.kube/config) or from in-cluster service account environment variables.
func NewClientset(kubeconfigPath string) (*kubernetes.Clientset, error) {
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()

	if kubeconfigPath != "" {
		fmt.Printf("  - Using provided kubeconfig path: %s\n", kubeconfigPath)
		loadingRules.ExplicitPath = kubeconfigPath
	} else {
		// If no path is provided, search for the default kubeconfig file.
		home, err := os.UserHomeDir()
		if err == nil {
			defaultPath := filepath.Join(home, ".kube", "config")
			if _, err := os.Stat(defaultPath); err == nil {
				fmt.Printf("  - Using default kubeconfig path: %s\n", defaultPath)
				loadingRules.ExplicitPath = defaultPath
			} else {
				fmt.Println("  - No kubeconfig path provided and default not found. Assuming in-cluster configuration.")
			}
		} else {
			fmt.Println("  - Could not determine home directory. Assuming in-cluster configuration.")
		}
	}

	configOverrides := &clientcmd.ConfigOverrides{}
	config, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides).ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("could not create kubernetes client config: %w", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("could not create kubernetes clientset: %w", err)
	}
	return clientset, nil
}
