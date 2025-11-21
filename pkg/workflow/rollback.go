package workflow
import ("go_certs_rotation/pkg/log"; "go_certs_rotation/pkg/task"; "path/filepath")
func (w *Workflow) Rollback() error {
	log.L().Info("--- Starting Full Rollback Phase ---")
	allNodes := append(w.topology.MasterNodes, w.topology.EtcdNodes...) // Simplified unique
	for _, node := range allNodes {
		l := log.L().With("node", node.Name)
		l.Info("--- Rolling back node ---")
		runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath); if err != nil { return err }; defer runner.Close()

		nodeOldDir := filepath.Join(w.config.Workspace, node.Name, "old")
		if err := w.uploadDirectoryContents(runner, nodeOldDir+"/kubernetes", "/etc/kubernetes"); err != nil { return err }
		if err := w.uploadDirectoryContents(runner, nodeOldDir+"/etcd-ssl", "/etc/ssl/etcd/ssl"); err != nil { return err }
		if _, err := runner.Run("systemctl restart kubelet"); err != nil { return err }
	}
	return nil
}
