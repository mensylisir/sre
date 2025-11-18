package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/log"
	"go_certs_rotation/pkg/task"
	"path/filepath"
)

// Rollback handles the restoration of backed-up certificates.
func (w *Workflow) Rollback() error {
	log.L().Info("--- Starting Rollback Phase ---")

	for _, node := range w.topology.MasterNodes {
		l := log.L().With("node", node.Name, "ip", node.InternalIP)
		l.Info("--- Rolling back certificates on node ---")
		runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
		if err != nil {
			return fmt.Errorf("could not create runner for %s: %w", node.Name, err)
		}
		defer runner.Close()

		localPath := filepath.Join(w.workspace.localBackupDir, fmt.Sprintf("%s-apiserver.crt", node.Name))
		remotePath := "/etc/kubernetes/pki/apiserver.crt"

		l.Info("Restoring file", "local_path", localPath, "remote_path", remotePath)
		if err := runner.Upload(localPath, remotePath); err != nil {
			return fmt.Errorf("failed to upload backed-up certificate to %s: %w", node.Name, err)
		}

		l.Info("Restarting kubelet...")
		if _, err := runner.Run("systemctl restart kubelet"); err != nil {
			return fmt.Errorf("failed to restart kubelet on %s: %w", node.Name, err)
		}
	}

	log.L().Info("--- Rollback Phase Complete ---")
	return nil
}
