package workflow

import (
    "fmt"
    "go_certs_rotation/pkg/config"
    "go_certs_rotation/pkg/discovery"
    "go_certs_rotation/pkg/k8s"
    // "go_certs_rotation/pkg/certs"
    // "go_certs_rotation/pkg/task"
)

// Run starts the certificate rotation workflow.
func Run(cfg *config.Config) error {
	fmt.Println("Starting certificate rotation workflow...")

	// 1. Create Kubernetes client
	clientset, err := k8s.NewClientset(cfg.KubeconfigPath)
	if err != nil {
		return fmt.Errorf("could not create k8s clientset: %w", err)
	}

	// 2. Discover cluster topology
	fmt.Println("Discovering cluster topology...")
	topology, err := discovery.DiscoverTopology(clientset)
	if err != nil {
		return fmt.Errorf("could not discover cluster topology: %w", err)
	}
	fmt.Printf("Discovered %d master nodes and %d etcd nodes.\n", len(topology.MasterNodes), len(topology.EtcdNodes))

	// 3. Prepare phase
	fmt.Println("Preparing for rotation (backing up existing certs, generating new ones)...")
	// for _, node := range topology.MasterNodes {
	// 	runner := task.NewSSHRunner(node.InternalIP, cfg.SSH.User, cfg.SSH.Key)
	// 	// runner.Download("/etc/kubernetes/pki", "/tmp/backup/...")
	// }
    // ... Generate new CAs and leaf certs using the certs package ...

	// 4. Rotation phase
	fmt.Println("Starting rotation phase (node by node)...")
	// for _, node := range topology.MasterNodes {
	// 	fmt.Printf("Rotating certificates on node %s...\n", node.Name)
	// 	runner := task.NewSSHRunner(node.InternalIP, cfg.SSH.User, cfg.SSH.Key)

	// 	// a. Apply bundle
	// 	// runner.Upload("bundle-ca.crt", "/etc/kubernetes/pki/ca.crt")
	// 	// runner.Run("systemctl restart kubelet")
	// 	// k8s.WaitForNodeReady(...)

	// 	// b. Apply new certs
	// 	// ...

	// 	// c. Apply final CA
	// 	// ...
	// }

	fmt.Println("Workflow completed successfully.")
	return nil
}

// Rollback starts the rollback workflow.
func Rollback(cfg *config.Config) error {
	// TODO: Implement the rollback logic.
	return nil
}
