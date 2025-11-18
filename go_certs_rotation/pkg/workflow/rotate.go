package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/k8s"
	"go_certs_rotation/pkg/task"
	"path/filepath"
	"time"
)

// Rotate handles the node-by-node certificate rotation.
func (w *Workflow) Rotate() error {
	fmt.Println("--- Starting Rotation Phase ---")

	for _, node := range w.topology.MasterNodes {
		fmt.Printf("--- Rotating certificates on node: %s ---\n", node.Name)
		runner, err := task.NewSSHRunner(node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
		if err != nil {
			return fmt.Errorf("could not create SSH runner for %s: %w", node.Name, err)
		}

		// 1. Distribute bundled CA and restart
		fmt.Printf("  - Step 1: Distributing bundled CA to %s...\n", node.Name)
		bundlePath := filepath.Join(w.workspace.localNewCertsDir, "ca-bundle.crt")
		if err := runner.Upload(bundlePath, "/etc/kubernetes/pki/ca.crt"); err != nil {
			return err
		}
		if _, err := runner.Run("systemctl restart kubelet"); err != nil {
			return err
		}
		if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil {
			return err
		}

		// 2. Distribute new leaf certificates and restart
		fmt.Printf("  - Step 2: Distributing new leaf certificates to %s...\n", node.Name)
		leafCertPath := filepath.Join(w.workspace.localNewCertsDir, "apiserver.crt")
		leafKeyPath := filepath.Join(w.workspace.localNewCertsDir, "apiserver.key")
		if err := runner.Upload(leafCertPath, "/etc/kubernetes/pki/apiserver.crt"); err != nil {
			return err
		}
		if err := runner.Upload(leafKeyPath, "/etc/kubernetes/pki/apiserver.key"); err != nil {
			return err
		}
		if _, err := runner.Run("systemctl restart kubelet"); err != nil {
			return err
		}
		if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil {
			return err
		}

		// 3. Distribute final CA and restart
		fmt.Printf("  - Step 3: Distributing final CA to %s...\n", node.Name)
		finalCAPath := filepath.Join(w.workspace.localNewCertsDir, "k8s-ca.crt")
		if err := runner.Upload(finalCAPath, "/etc/kubernetes/pki/ca.crt"); err != nil {
			return err
		}
		if _, err := runner.Run("systemctl restart kubelet"); err != nil {
			return err
		}
		if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil {
			return err
		}

		fmt.Printf("--- Finished rotating certificates on node: %s ---\n", node.Name)
	}

	fmt.Println("--- Rotation Phase Complete ---")
	return nil
}
