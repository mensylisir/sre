package workflow

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"go_certs_rotation/pkg/log"
	"io/ioutil"
	"path/filepath"
	"gopkg.in/yaml.v3"
)

func (w *Workflow) preparePart3_BundleAndUpdateConfigs() error {
	log.L().Info("--- Starting Prepare (Part 3/3): Real Bundling & Kubeconfig Update ---")

	// 1. Real CA Bundling
	log.L().Info("Creating real CA bundles by concatenating old and new CAs...")
	firstMasterOldDir := filepath.Join(w.config.Workspace, w.topology.MasterNodes[0].Name, "old")

	oldK8sCaBytes, err := ioutil.ReadFile(filepath.Join(firstMasterOldDir, "kubernetes", "pki", "ca.crt"))
	if err != nil { return fmt.Errorf("failed to read old k8s ca: %w", err) }
	k8sBundle := bytes.Join([][]byte{oldK8sCaBytes, generatedCAs["k8sCACert"]}, []byte("\n"))

	// oldEtcdCaBytes, err := ...
	// etcdBundle := ...

	// 2. Precise Kubeconfig Updates for all nodes
	log.L().Info("Updating all backed up kubeconfig files...")
	allNodes := append(w.topology.MasterNodes, w.topology.EtcdNodes...) // Simplified unique
	for _, node := range allNodes {
		l := log.L().With("node", node.Name)
		l.Debug("Updating kubeconfigs for node...")
		nodeOldDir := filepath.Join(w.config.Workspace, node.Name, "old")
		nodeBundleDir := filepath.Join(w.config.Workspace, node.Name, "bundle")

		// Find all .conf files in the old directory
		confFiles, err := filepath.Glob(filepath.Join(nodeOldDir, "*.conf"))
		if err != nil { continue } // No conf files for this node, e.g., pure etcd

		for _, confFile := range confFiles {
			destFile := filepath.Join(nodeBundleDir, filepath.Base(confFile))
			l.Debug("Updating kubeconfig", "source", confFile, "destination", destFile)
			if err := w.updateKubeconfigCA(confFile, destFile, k8sBundle); err != nil {
				return fmt.Errorf("failed to update %s for node %s: %w", confFile, node.Name, err)
			}
		}
	}

	log.L().Info("--- Prepare (Part 3/3) Complete ---")
	return nil
}

// updateKubeconfigCA precisely updates the certificate-authority-data in a kubeconfig file.
func (w *Workflow) updateKubeconfigCA(srcPath, destPath string, caBundle []byte) error {
    content, err := ioutil.ReadFile(srcPath); if err != nil { return err }

    var kubeconfig map[string]interface{}
    if err := yaml.Unmarshal(content, &kubeconfig); err != nil {
        // If it's not a valid YAML, it's not a kubeconfig we should modify. Just copy it.
        return ioutil.WriteFile(destPath, content, 0644)
    }

    clusters, ok := kubeconfig["clusters"].([]interface{}); if !ok { return fmt.Errorf("invalid kubeconfig format: 'clusters' is not a list") }

    for _, c := range clusters {
        cluster, ok := c.(map[string]interface{}); if !ok { continue }
        clusterDetails, ok := cluster["cluster"].(map[string]interface{}); if !ok { continue }

        // Update the CA data
        if _, exists := clusterDetails["certificate-authority-data"]; exists {
            clusterDetails["certificate-authority-data"] = base64.StdEncoding.EncodeToString(caBundle)
        }
    }

    newContent, err := yaml.Marshal(&kubeconfig); if err != nil { return err }
    return ioutil.WriteFile(destPath, newContent, 0644)
}
