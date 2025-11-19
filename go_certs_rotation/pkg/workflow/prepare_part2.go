package workflow

import (
	"crypto/x509"
	"fmt"
	"go_certs_rotation/pkg/certs"
	"go_certs_rotation/pkg/log"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
)

// This map will store the generated CAs for use in the next step.
var generatedCAs = make(map[string][]byte)

func (w *Workflow) preparePart2_GenerateCerts() error {
	log.L().Info("--- Starting Prepare (Part 2/3): 1:1 Certificate Generation ---")

	// 1. Generate New CAs
	log.L().Info("Generating new CAs...")
	k8sCACert, k8sCAKey, _ := certs.GenerateCertificate(certs.CertSpec{Subject: mustParseSubject("/CN=kubernetes"), ExpiryDays: 3650, IsCA: true}, nil, nil)
	etcdCACert, etcdCAKey, _ := certs.GenerateCertificate(certs.CertSpec{Subject: mustParseSubject("/CN=etcd-ca"), ExpiryDays: 3650, IsCA: true}, nil, nil)
	frontProxyCACert, frontProxyCAKey, _ := certs.GenerateCertificate(certs.CertSpec{Subject: mustParseSubject("/CN=front-proxy-ca"), ExpiryDays: 3650, IsCA: true}, nil, nil)

	// Store for later use
	generatedCAs["k8sCACert"], generatedCAs["k8sCAKey"] = k8sCACert, k8sCAKey
	generatedCAs["etcdCACert"], generatedCAs["etcdCAKey"] = etcdCACert, etcdCAKey
	generatedCAs["frontProxyCACert"], generatedCAs["frontProxyCAKey"] = frontProxyCACert, frontProxyCAKey

	// 2. Generate 1:1 Leaf Certs for each node
	log.L().Info("Generating 1:1 leaf certificates for each node...")
	allNodes := append(w.topology.MasterNodes, w.topology.EtcdNodes...) // Simplified unique
	for _, node := range allNodes {
		hostname := node.Name
		l := log.L().With("node", hostname)
		l.Info("Generating certificates for node...")

		newDir := filepath.Join(w.config.Workspace, hostname, "new")
		newPkiDir := filepath.Join(newDir, "kubernetes", "pki")
		newEtcdSslDir := filepath.Join(newDir, "etcd-ssl")
		os.MkdirAll(newPkiDir, 0755); os.MkdirAll(newEtcdSslDir, 0755)

		// Kubernetes Certs
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject("/CN=kube-apiserver"), SANs: extractedSANs["k8s-apiserver"], ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}, k8sCACert, k8sCAKey, newPkiDir, "apiserver.crt")
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject("/CN=kube-apiserver-kubelet-client/O=system:masters"), ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}}, k8sCACert, k8sCAKey, newPkiDir, "apiserver-kubelet-client.crt")
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject("/CN=front-proxy-client"), ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}}, frontProxyCACert, frontProxyCAKey, newPkiDir, "front-proxy-client.crt")

		saPub, saKey, _ := certs.GenerateSAKeyPair()
		ioutil.WriteFile(filepath.Join(newPkiDir, "sa.pub"), saPub, 0644)
		ioutil.WriteFile(filepath.Join(newPkiDir, "sa.key"), saKey, 0600)

		// Etcd Certs
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject(fmt.Sprintf("/CN=etcd-admin-%s", hostname)), SANs: extractedSANs["etcd-admin"], ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}}, etcdCACert, etcdCAKey, newEtcdSslDir, fmt.Sprintf("admin-%s.pem", hostname))
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject(fmt.Sprintf("/CN=etcd-node-%s", hostname)), SANs: extractedSANs["etcd-node"], ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}}, etcdCACert, etcdCAKey, newEtcdSslDir, fmt.Sprintf("node-%s.pem", hostname))
		generateAndWrite(certs.CertSpec{Subject: mustParseSubject(fmt.Sprintf("/CN=etcd-member-%s", hostname)), SANs: extractedSANs["etcd-member"], ExpiryDays: 365, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}}, etcdCACert, etcdCAKey, newEtcdSslDir, fmt.Sprintf("member-%s.pem", hostname))
	}

	log.L().Info("--- Prepare (Part 2/3) Complete ---")
	return nil
}

// Helper to generate and write a certificate and key
func generateAndWrite(spec certs.CertSpec, caCert, caKey []byte, dir, name string) {
	cert, key, err := certs.GenerateCertificate(spec, caCert, caKey)
	if err != nil { panic(err) } // Should not happen with correct inputs

	keyName := ""
	if strings.HasSuffix(name, ".crt") {
		keyName = strings.TrimSuffix(name, ".crt") + ".key"
	} else if strings.HasSuffix(name, ".pem") {
		keyName = strings.TrimSuffix(name, ".pem") + "-key.pem"
	} else {
		keyName = name + ".key" // Fallback
	}

	ioutil.WriteFile(filepath.Join(dir, name), cert, 0644)
	ioutil.WriteFile(filepath.Join(dir, keyName), key, 0600)
}
