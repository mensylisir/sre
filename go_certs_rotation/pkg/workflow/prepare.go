package workflow

import (
	"crypto/x509"
	"fmt"
	"go_certs_rotation/pkg/certs"
	"go_certs_rotation/pkg/task"
	"io/ioutil"
	"os"
	"path/filepath"
)

// Prepare executes the full preparation phase, mirroring the logic of 01-prepare.sh.
func (w *Workflow) Prepare() error {
	fmt.Println("--- Starting Full Prepare Phase ---")

	// 1. Create local workspace directories for each node
	nodeDirs := make(map[string]map[string]string)
	for _, node := range w.topology.MasterNodes { // Assuming all nodes are masters for simplicity now
		hostname := node.Name
		nodeDirs[hostname] = make(map[string]string)
		nodeDirs[hostname]["base"] = filepath.Join(w.config.Workspace, hostname)
		nodeDirs[hostname]["old"] = filepath.Join(w.config.Workspace, hostname, "old")
		nodeDirs[hostname]["new"] = filepath.Join(w.config.Workspace, hostname, "new")
		nodeDirs[hostname]["bundle"] = filepath.Join(w.config.Workspace, hostname, "bundle")
		for _, dir := range nodeDirs[hostname] {
			if err := os.MkdirAll(dir, 0755); err != nil {
				return err
			}
		}
	}

	// 2. Backup certificates from the first master (as a representative sample)
	// In a real scenario, we might want to do this for all nodes.
	firstMaster := w.topology.MasterNodes[0]
	runner, err := task.NewRunner(false, firstMaster.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
	if err != nil {
		return err
	}

    // Placeholder for actual backup logic, as Download is simplified
	fmt.Println("Backing up certificates (placeholder)...")


	// 3. Generate new CAs
	fmt.Println("Generating new CAs...")
	k8sCASpec := certs.CertSpec{Subject: mustParseSubject("/CN=kubernetes"), ExpiryDays: 3650, IsCA: true}
	k8sCACert, k8sCAKey, _ := certs.GenerateCertificate(k8sCASpec, nil, nil)

	etcdCASpec := certs.CertSpec{Subject: mustParseSubject("/CN=etcd-ca"), ExpiryDays: 3650, IsCA: true}
	etcdCACert, etcdCAKey, _ := certs.GenerateCertificate(etcdCASpec, nil, nil)

	frontProxyCASpec := certs.CertSpec{Subject: mustParseSubject("/CN=front-proxy-ca"), ExpiryDays: 3650, IsCA: true}
	frontProxyCACert, frontProxyCAKey, _ := certs.GenerateCertificate(frontProxyCASpec, nil, nil)

	// 4. Extract SANs (using placeholders for now, as backup is not fully implemented)
	fmt.Println("Extracting SANs (using placeholders)...")
	k8sApiserverSANs := []string{ "kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.cluster.local", "10.96.0.1", "localhost", "127.0.0.1" }
	etcdSANs := []string{ "localhost", "127.0.0.1" }
	for _, node := range w.topology.EtcdNodes {
		etcdSANs = append(etcdSANs, node.Name, node.InternalIP)
	}


	// 5. Generate all new leaf certificates for each node
	fmt.Println("Generating new leaf certificates for each node...")
	for _, node := range w.topology.MasterNodes {
		hostname := node.Name
		newPkiDir := filepath.Join(nodeDirs[hostname]["new"], "kubernetes", "pki")
		newEtcdSslDir := filepath.Join(nodeDirs[hostname]["new"], "etcd-ssl")
		os.MkdirAll(newPkiDir, 0755)
		os.MkdirAll(newEtcdSslDir, 0755)

		// K8s certs
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject("/CN=kube-apiserver"), SANs: k8sApiserverSANs, ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}, k8sCACert, k8sCAKey, newPkiDir, "apiserver")
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject("/CN=kube-apiserver-kubelet-client/O=system:masters"), ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}}, k8sCACert, k8sCAKey, newPkiDir, "apiserver-kubelet-client")
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject("/CN=front-proxy-client"), ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}}, frontProxyCACert, frontProxyCAKey, newPkiDir, "front-proxy-client")

		saPub, saKey, _ := certs.GenerateSAKeyPair()
		ioutil.WriteFile(filepath.Join(newPkiDir, "sa.pub"), saPub, 0644)
		ioutil.WriteFile(filepath.Join(newPkiDir, "sa.key"), saKey, 0600)

		// Etcd certs
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject(fmt.Sprintf("/CN=etcd-admin-%s", hostname)), SANs: etcdSANs, ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}}, etcdCACert, etcdCAKey, newEtcdSslDir, fmt.Sprintf("admin-%s.pem", hostname))
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject(fmt.Sprintf("/CN=etcd-node-%s", hostname)), SANs: etcdSANs, ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}}, etcdCACert, etcdCAKey, newEtcdSslDir, fmt.Sprintf("node-%s.pem", hostname))
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject(fmt.Sprintf("/CN=etcd-member-%s", hostname)), SANs: etcdSANs, ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}}, etcdCACert, etcdCAKey, newEtcdSslDir, fmt.Sprintf("member-%s.pem", hostname))
	}

	// 6. Create Bundles (Simplified - would combine old and new CAs in a real scenario)
	fmt.Println("Creating bundled CAs...")
	for _, node := range w.topology.MasterNodes {
		hostname := node.Name
		bundlePkiDir := filepath.Join(nodeDirs[hostname]["bundle"], "kubernetes", "pki")
		bundleEtcdSslDir := filepath.Join(nodeDirs[hostname]["bundle"], "etcd-ssl")
		os.MkdirAll(bundlePkiDir, 0755)
		os.MkdirAll(bundleEtcdSslDir, 0755)

		ioutil.WriteFile(filepath.Join(bundlePkiDir, "ca.crt"), k8sCACert, 0644)
		ioutil.WriteFile(filepath.Join(bundleEtcdSslDir, "ca.pem"), etcdCACert, 0644)
	}

	fmt.Println("--- Full Prepare Phase Complete ---")
	return nil
}

// Helper to parse subject and panic on error for specs
func mustParseSubject(s string) pkix.Name {
	name, err := certs.ParseSubject(s)
	if err != nil {
		panic(err)
	}
	return name
}

// Helper to generate and write a certificate and key
func generateAndWrite(spec certs.CertSpec, caCert, caKey []byte, dir, name string) {
	cert, key, err := certs.GenerateCertificate(spec, caCert, caKey)
	if err != nil {
		panic(err)
	}

	// remove .pem from name if present for key file name
	keyName := strings.TrimSuffix(name, ".pem") + ".key"
	if name.EndsWith(".pem") {
		keyName = strings.TrimSuffix(name, ".pem") + "-key.pem"
	}

	ioutil.WriteFile(filepath.Join(dir, name), cert, 0644)
	ioutil.WriteFile(filepath.Join(dir, keyName), key, 0600)
}
