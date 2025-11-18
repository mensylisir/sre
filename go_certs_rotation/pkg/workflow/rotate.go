package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/k8s"
	"go_certs_rotation/pkg/task"
	"path/filepath"
	"time"
)

// Rotate executes the full, three-stage rotation for each node.
func (w *Workflow) Rotate() error {
	fmt.Println("--- Starting Full Rotation Phase ---")

	for _, node := range w.topology.MasterNodes {
		fmt.Printf("--- Rotating node: %s ---\n", node.Name)
		runner, err := task.NewRunner(false, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
		if err != nil {
			return err
		}

		nodeDirs := map[string]string{
			"bundle": filepath.Join(w.config.Workspace, node.Name, "bundle"),
			"new":    filepath.Join(w.config.Workspace, node.Name, "new"),
		}

		// Stage 1: Apply Bundle (Trust Expansion)
		fmt.Printf("  [1/3] Applying bundle configuration to %s...\n", node.Name)
		// This is a simplified version. A real implementation would also update kubeconfig files.
		if err := runner.Upload(filepath.Join(nodeDirs["bundle"], "kubernetes", "pki", "ca.crt"), "/etc/kubernetes/pki/ca.crt"); err != nil { return err }
		if err := runner.Upload(filepath.Join(nodeDirs["bundle"], "etcd-ssl", "ca.pem"), "/etc/ssl/etcd/ssl/ca.pem"); err != nil { return err }
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err }

		// Stage 2: Apply New Leaf Certificates (Certificate Rotation)
		fmt.Printf("  [2/3] Applying new leaf certificates to %s...\n", node.Name)
        // Sync all new certs/keys, but NOT the CAs.
        // A real implementation would use rsync with --exclude='ca.crt' --exclude='ca.key'
        newPkiDir := filepath.Join(nodeDirs["new"], "kubernetes", "pki")
		if err := runner.Upload(filepath.Join(newPkiDir, "apiserver.crt"), "/etc/kubernetes/pki/apiserver.crt"); err != nil { return err }
		if err := runner.Upload(filepath.Join(newPkiDir, "apiserver.key"), "/etc/kubernetes/pki/apiserver.key"); err != nil { return err }
        // ... upload all other leaf certs and keys ...
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err }

		// Stage 3: Apply Final Config (Trust Contraction)
		fmt.Printf("  [3/3] Applying final configuration to %s...\n", node.Name)
		// Now we upload the new CAs.
		if err := runner.Upload(filepath.Join(newPkiDir, "ca.crt"), "/etc/kubernetes/pki/ca.crt"); err != nil { return err }
        // ... upload final etcd CA and other final configs ...
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err }

		fmt.Printf("--- Node %s rotation complete ---\n", node.Name)
	}

	fmt.Println("--- Full Rotation Phase Complete ---")
	return nil
}
