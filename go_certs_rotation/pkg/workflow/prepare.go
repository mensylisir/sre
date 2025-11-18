package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/certs"
	"go_certs_rotation/pkg/log"
	"go_certs_rotation/pkg/task"
	"io/ioutil"
	"os"
	"path/filepath"
)

// Prepare handles the backup and new certificate generation phase.
func (w *Workflow) Prepare() error {
	log.L().Info("--- Starting Prepare Phase ---")

	if err := os.MkdirAll(w.workspace.localBackupDir, 0755); err != nil { return err }
	if err := os.MkdirAll(w.workspace.localNewCertsDir, 0755); err != nil { return err }

	log.L().Info("Backing up existing certificates from master nodes...")
	for _, node := range w.topology.MasterNodes {
		l := log.L().With("node", node.Name, "ip", node.InternalIP)
		l.Debug("Creating runner for backup")
		runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
		if err != nil {
			return err
		}
		defer runner.Close()

		remotePath := "/etc/kubernetes/pki/apiserver.crt"
		localPath := filepath.Join(w.workspace.localBackupDir, fmt.Sprintf("%s-apiserver.crt", node.Name))
		l.Info("Backing up file", "remote_path", remotePath, "local_path", localPath)
		if err := runner.Download(remotePath, localPath); err != nil {
			l.Warn("Could not back up file", "path", remotePath, "error", err)
		}
	}

	log.L().Info("Generating new CAs...")
    k8sCASubj, _ := certs.ParseSubject("/CN=kubernetes")
    k8sCACert, k8sCAKey, err := certs.GenerateCA(k8sCASubj, 3650)
    if err != nil { return err }
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "k8s-ca.crt"), k8sCACert, 0644)
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "k8s-ca.key"), k8sCAKey, 0600)

	log.L().Info("Generating new leaf certificates...")
    apiserverSubj, _ := certs.ParseSubject("/CN=kube-apiserver")
    sans := []string{"127.0.0.1", "kubernetes.default"}
    apiCert, apiKey, err := certs.GenerateLeafCert(apiserverSubj, sans, 365, nil, k8sCACert, k8sCAKey)
    if err != nil { return err }
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "apiserver.crt"), apiCert, 0644)
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "apiserver.key"), apiKey, 0600)

	log.L().Info("Creating bundled CA for transition...")
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "ca-bundle.crt"), k8sCACert, 0644)

	log.L().Info("--- Prepare Phase Complete ---")
	return nil
}
