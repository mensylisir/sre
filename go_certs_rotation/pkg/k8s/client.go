package k8s

import (
	"k8s.io.client-go/kubernetes"
	"k8s.io.client-go/tools/clientcmd"
)

// NewClientset creates a new Kubernetes clientset from a kubeconfig file path.
func NewClientset(kubeconfigPath string) (*kubernetes.Clientset, error) {
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	loadingRules.ExplicitPath = kubeconfigPath
	configOverrides := &clientcmd.ConfigOverrides{}

	config, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides).ClientConfig()
	if err != nil {
		return nil, err
	}

	return kubernetes.NewForConfig(config)
}
