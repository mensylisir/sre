package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/task"
	"path/filepath"
)

// Rollback handles the restoration of backed-up certificates.
func (w *Workflow) Rollback() error {
	fmt.Println("--- Starting Rollback Phase ---")

	// This is a simplified rollback. It restores the backed-up apiserver certificate
	// to all master nodes. A real implementation would need to be more granular.
	for _, node := range w.topology.MasterNodes {
		fmt.Printf("--- Rolling back certificates on node: %s ---\n", node.Name)
		runner, err := task.NewSSHRunner(node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
		if err != nil {
			return fmt.Errorf("could not create SSH runner for %s: %w", node.Name, err)
		}

		localPath := filepath.Join(w.workspace.localBackupDir, fmt.Sprintf("%s-apiserver.crt", node.Name))
		remotePath := "/etc/kubernetes/pki/apiserver.crt"

		fmt.Printf("  - Restoring %s on %s...\n", remotePath, node.Name)
		if err := runner.Upload(localPath, remotePath); err != nil {
			return fmt.Errorf("failed to upload backed-up certificate to %s: %w", node.Name, err)
		}

		fmt.Printf("  - Restarting kubelet on %s...\n", node.Name)
		if _, err := runner.Run("systemctl restart kubelet"); err != nil {
			return fmt.Errorf("failed to restart kubelet on %s: %w", node.Name, err)
		}
	}

	fmt.Println("--- Rollback Phase Complete ---")
	return nil
}
