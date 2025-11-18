package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/certs"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/discovery"
	"go_certs_rotation/pkg/task"
	"io/ioutil"
	"os"
	"path/filepath"
)

// Prepare handles the backup and new certificate generation phase.
func (w *Workflow) Prepare() error {
	fmt.Println("--- Starting Prepare Phase ---")

	// Create local workspace directories
	if err := os.MkdirAll(w.workspace.localBackupDir, 0755); err != nil { return err }
	if err := os.MkdirAll(w.workspace.localNewCertsDir, 0755); err != nil { return err }

	// Backup certificates from each master node
	fmt.Println("Backing up existing certificates from master nodes...")
	for _, node := range w.topology.MasterNodes {
		runner, err := task.NewSSHRunner(node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
		if err != nil {
			return err
		}
        // Simplified: In a real scenario, we'd download the entire pki dir.
		remotePath := "/etc/kubernetes/pki/apiserver.crt"
		localPath := filepath.Join(w.workspace.localBackupDir, fmt.Sprintf("%s-apiserver.crt", node.Name))
		if err := runner.Download(remotePath, localPath); err != nil {
			fmt.Printf("Warning: could not back up %s from %s: %v\n", remotePath, node.Name, err)
		}
	}

    // In a real implementation, we would also extract SANs from the backed-up certs here.

	// Generate new CAs
	fmt.Println("Generating new CAs...")
    k8sCASubj, _ := certs.ParseSubject("/CN=kubernetes")
    k8sCACert, k8sCAKey, err := certs.GenerateCA(k8sCASubj, 3650)
    if err != nil { return err }
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "k8s-ca.crt"), k8sCACert, 0644)
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "k8s-ca.key"), k8sCAKey, 0600)

    // Generate new leaf certificates (example for apiserver)
    fmt.Println("Generating new leaf certificates...")
    apiserverSubj, _ := certs.ParseSubject("/CN=kube-apiserver")
    // In a real implementation, SANs would be discovered or configurable.
    sans := []string{"127.0.0.1", "kubernetes.default"}
    apiCert, apiKey, err := certs.GenerateLeafCert(apiserverSubj, sans, 365, nil, k8sCACert, k8sCAKey)
    if err != nil { return err }
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "apiserver.crt"), apiCert, 0644)
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "apiserver.key"), apiKey, 0600)

	// Create bundled CA
    fmt.Println("Creating bundled CA for transition...")
	// For simplicity, we'll just use the new CA as the bundle for now.
    // A real implementation would combine the old and new CAs.
    ioutil.WriteFile(filepath.Join(w.workspace.localNewCertsDir, "ca-bundle.crt"), k8sCACert, 0644)

	fmt.Println("--- Prepare Phase Complete ---")
	return nil
}
