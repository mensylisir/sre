package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/k8s"
	"go_certs_rotation/pkg/log"
	"go_certs_rotation/pkg/task"
	"path/filepath"
	"time"
)

// Rotate handles the node-by-node certificate rotation.
func (w *Workflow) Rotate() error {
	log.L().Info("--- Starting Rotation Phase ---")

	for _, node := range w.topology.MasterNodes {
		l := log.L().With("node", node.Name, "ip", node.InternalIP)
		l.Info("--- Rotating certificates on node ---")
		runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
		if err != nil {
			return fmt.Errorf("could not create runner for %s: %w", node.Name, err)
		}
		defer runner.Close()

		l.Info("Step 1: Distributing bundled CA...")
		bundlePath := filepath.Join(w.workspace.localNewCertsDir, "ca-bundle.crt")
		if err := runner.Upload(bundlePath, "/etc/kubernetes/pki/ca.crt"); err != nil { return err }
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if !w.dryRun {
			if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err }
		}

		l.Info("Step 2: Distributing new leaf certificates...")
		leafCertPath := filepath.Join(w.workspace.localNewCertsDir, "apiserver.crt")
		leafKeyPath := filepath.Join(w.workspace.localNewCertsDir, "apiserver.key")
		if err := runner.Upload(leafCertPath, "/etc/kubernetes/pki/apiserver.crt"); err != nil { return err }
		if err := runner.Upload(leafKeyPath, "/etc/kubernetes/pki/apiserver.key"); err != nil { return err }
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if !w.dryRun {
			if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err }
		}

		l.Info("Step 3: Distributing final CA...")
		finalCAPath := filepath.Join(w.workspace.localNewCertsDir, "k8s-ca.crt")
		if err := runner.Upload(finalCAPath, "/etc/kubernetes/pki/ca.crt"); err != nil { return err }
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if !w.dryRun {
			if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err }
		}

		l.Info("--- Finished rotating certificates on node ---")
	}

	log.L().Info("--- Rotation Phase Complete ---")
	return nil
}
