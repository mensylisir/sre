package workflow
import ("go_certs_rotation/pkg/log"; "go_certs_rotation/pkg/task"; "path/filepath")
func (w *Workflow) Rollback() error {
	log.L().Info("--- Starting Full Rollback Phase ---")
	for _, node := range w.topology.MasterNodes {
		l := log.L().With("node", node.Name, "ip", node.InternalIP)
		l.Info("--- Rolling back node ---")
		runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath); if err != nil { return err }; defer runner.Close()

		nodeOldDir := filepath.Join(w.config.Workspace, node.Name, "old")
		if err := runner.Upload(nodeOldDir+"/pki/", "/etc/kubernetes/pki/"); err != nil { return err }
		if err := runner.Upload(nodeOldDir+"/admin.conf", "/etc/kubernetes/admin.conf"); err != nil { return err }
		// ... upload all other backed up files ...
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
	}
	log.L().Info("--- Full Rollback Phase Complete ---")
	return nil
}
