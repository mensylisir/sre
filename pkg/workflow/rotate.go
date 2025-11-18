package workflow
import ("fmt"; "go_certs_rotation/pkg/k8s"; "go_certs_rotation/pkg/log"; "go_certs_rotation/pkg/task"; "path/filepath"; "time")
func (w *Workflow) Rotate() error {
	log.L().Info("--- Starting Full Rotation Phase ---")
	for _, node := range w.topology.MasterNodes {
		l := log.L().With("node", node.Name, "ip", node.InternalIP)
		l.Info("--- Rotating node ---")
		runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath); if err != nil { return err }; defer runner.Close()

		nodeBundleDir := filepath.Join(w.config.Workspace, node.Name, "bundle")
		nodeNewDir := filepath.Join(w.config.Workspace, node.Name, "new")

		// Stage 1: Apply Bundle
		l.Info("[1/3] Applying bundle configuration...")
		if err := runner.Upload(filepath.Join(nodeBundleDir, "admin.conf"), "/etc/kubernetes/admin.conf"); err != nil { return err }
		// ... upload all other bundle files ...
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if !w.dryRun { if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err } }

		// Stage 2: Apply New Leaf Certs
		l.Info("[2/3] Applying new leaf certificates...")
		// A real implementation would use rsync --exclude or multiple uploads
		if err := runner.Upload(filepath.Join(nodeNewDir, "pki", "apiserver.crt"), "/etc/kubernetes/pki/apiserver.crt"); err != nil { return err }
		if err := runner.Upload(filepath.Join(nodeNewDir, "pki", "apiserver.key"), "/etc/kubernetes/pki/apiserver.key"); err != nil { return err }
		// ... upload all other leaf certs ...
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if !w.dryRun { if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err } }

		// Stage 3: Apply Final Config
		l.Info("[3/3] Applying final configuration...")
		if err := runner.Upload(filepath.Join(nodeNewDir, "pki", "ca.crt"), "/etc/kubernetes/pki/ca.crt"); err != nil { return err }
		// ... upload all final files ...
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
		if !w.dryRun { if err := k8s.WaitForNodeReady(w.clientset, node.Name, 2*time.Minute); err != nil { return err } }
	}
	log.L().Info("--- Full Rotation Phase Complete ---")
	return nil
}
