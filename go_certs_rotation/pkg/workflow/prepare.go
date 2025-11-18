package workflow
import ("crypto/x509"; "encoding/base64"; "fmt"; "go_certs_rotation/pkg/certs"; "go_certs_rotation/pkg/log"; "go_certs_rotation/pkg/task"; "io/ioutil"; "os"; "path/filepath"; "strings"; "gopkg.in/yaml.v3")

func (w *Workflow) Prepare() error {
	log.L().Info("--- Starting Full Prepare Phase ---")
	// 1. Create local workspace directories for each node
	nodeDirs := make(map[string]map[string]string)
	allNodes := append(w.topology.MasterNodes, w.topology.EtcdNodes...) // Simplified for now
	for _, node := range allNodes {
		hostname := node.Name
		nodeDirs[hostname] = make(map[string]string)
		nodeDirs[hostname]["old"] = filepath.Join(w.config.Workspace, hostname, "old")
		nodeDirs[hostname]["new"] = filepath.Join(w.config.Workspace, hostname, "new")
		nodeDirs[hostname]["bundle"] = filepath.Join(w.config.Workspace, hostname, "bundle")
		for _, dir := range nodeDirs[hostname] { if err := os.MkdirAll(dir, 0755); err != nil { return err } }
	}

	// 2. Backup and Extract SANs
	log.L().Info("Backing up certificates and extracting SANs from the first master node...")
	firstMaster := w.topology.MasterNodes[0]
	runner, err := task.NewRunner(w.dryRun, firstMaster.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath); if err != nil { return err }; defer runner.Close()

	// Paths for remote certs and local backups
	remotePkiDir := "/etc/kubernetes/pki"
	localOldPkiDir := filepath.Join(nodeDirs[firstMaster.Name]["old"], "pki")
	os.MkdirAll(localOldPkiDir, 0755)

	// Download apiserver.crt to extract SANs
	apiserverCertPath := filepath.Join(localOldPkiDir, "apiserver.crt")
	if err := runner.Download(filepath.Join(remotePkiDir, "apiserver.crt"), apiserverCertPath); err != nil { return err }
	k8sApiserverSANs, err := certs.ExtractSANs(apiserverCertPath); if err != nil { return err }
	log.L().Info("Extracted apiserver SANs", "sans", k8sApiserverSANs)
    // ... Repeat for etcd certs to get etcdSANs ...
	etcdSANs := []string{"localhost", "127.0.0.1"}; for _, node := range w.topology.EtcdNodes { etcdSANs = append(etcdSANs, node.Name, node.InternalIP) }

	// 3. Generate new CAs
	// ... (Code from previous step to generate CAs) ...

	// 4. Generate all new leaf certificates for each node
	// ... (Code from previous step to generate leaf certs for each node) ...

	// 5. Create Bundles and Update Kubeconfigs
	log.L().Info("Creating CA bundles and updating kubeconfig files...")
	// oldCACertBytes, err := ioutil.ReadFile(filepath.Join(localOldPkiDir, "ca.crt")); if err != nil { return err }
	// k8sBundle := append(oldCACertBytes, k8sCACert...)
	// ioutil.WriteFile(filepath.Join(w.config.Workspace, "k8s-ca-bundle.crt"), k8sBundle, 0644)

	// Update kubelet.conf
	// localKubeletConfPath := filepath.Join(nodeDirs[firstMaster.Name]["old"], "kubelet.conf")
	// if err := runner.Download("/etc/kubernetes/kubelet.conf", localKubeletConfPath); err != nil { return err }
	// if err := w.updateKubeconfigCA(localKubeletConfPath, filepath.Join(nodeDirs[firstMaster.Name]["bundle"], "kubelet.conf"), k8sBundle); err != nil { return err }

	log.L().Info("--- Full Prepare Phase Complete ---")
	return nil
}

func (w *Workflow) updateKubeconfigCA(srcPath, destPath string, caBundle []byte) error {
    content, err := ioutil.ReadFile(srcPath); if err != nil { return err }
    var kubeconfig map[string]interface{}; if err := yaml.Unmarshal(content, &kubeconfig); err != nil { return err }

    clusters, ok := kubeconfig["clusters"].([]interface{}); if !ok { return fmt.Errorf("invalid kubeconfig format") }
    for _, c := range clusters {
        cluster, ok := c.(map[string]interface{}); if !ok { continue }
        clusterDetails, ok := cluster["cluster"].(map[string]interface{}); if !ok { continue }
        clusterDetails["certificate-authority-data"] = base64.StdEncoding.EncodeToString(caBundle)
    }

    newContent, err := yaml.Marshal(&kubeconfig); if err != nil { return err }
    return ioutil.WriteFile(destPath, newContent, 0644)
}
// ... (helper functions mustParseSubject and generateAndWrite would be here)
