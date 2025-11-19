package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/certs"
	"go_certs_rotation/pkg/log"
	"go_certs_rotation/pkg/task"
	"os"
	"path/filepath"
)

// This map stores the SANs extracted during the prepare phase.
var extractedSANs = make(map[string][]string)

func (w *Workflow) preparePart1_BackupAndExtractSANs() error {
	log.L().Info("--- Starting Prepare (Part 1/3): Full Backup & Real SANs Extraction ---")

	// 1. Create Directories & Perform Full Backup from Every Node
	allNodes := append(w.topology.MasterNodes, w.topology.EtcdNodes...) // Simplified unique
	for _, node := range allNodes {
		l := log.L().With("node", node.Name)
		l.Info("Creating directories and backing up node...")

		nodeOldDir := filepath.Join(w.config.Workspace, node.Name, "old")
		if err := os.MkdirAll(nodeOldDir, 0755); err != nil { return err }

		runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath); if err != nil { return err }; defer runner.Close()

		// Perform full backup of critical directories
		if err := runner.Download("/etc/kubernetes/", filepath.Join(nodeOldDir, "kubernetes")); err != nil { l.Warn("failed to backup /etc/kubernetes", "error", err) }
		if err := runner.Download("/etc/ssl/etcd/ssl/", filepath.Join(nodeOldDir, "etcd-ssl")); err != nil { l.Warn("failed to backup /etc/ssl/etcd/ssl", "error", err) }
	}

	// 2. Real SANs Extraction from the first master's backup
	log.L().Info("Extracting real SANs from backed up certificates...")
	firstMasterName := w.topology.MasterNodes[0].Name
	firstMasterOldDir := filepath.Join(w.config.Workspace, firstMasterName, "old")

	// Define certs to extract SANs from
	certsToExtract := map[string]string{
		"k8s-apiserver":     filepath.Join(firstMasterOldDir, "kubernetes", "pki", "apiserver.crt"),
		"etcd-admin":        filepath.Join(firstMasterOldDir, "etcd-ssl", fmt.Sprintf("admin-%s.pem", firstMasterName)),
		"etcd-node":         filepath.Join(firstMasterOldDir, "etcd-ssl", fmt.Sprintf("node-%s.pem", firstMasterName)),
		"etcd-member":       filepath.Join(firstMasterOldDir, "etcd-ssl", fmt.Sprintf("member-%s.pem", firstMasterName)),
	}

	for key, path := range certsToExtract {
		sans, err := certs.ExtractSANs(path)
		if err != nil {
			if w.dryRun {
				log.L().Warn("Could not extract SANs in dry-run mode (this is expected)", "cert", key, "path", path)
				extractedSANs[key] = []string{"localhost", "127.0.0.1"} // Use a default for dry-run
				continue
			}
			return fmt.Errorf("failed to extract SANs for %s from %s: %w", key, path, err)
		}
		log.L().Info("Successfully extracted SANs", "cert", key, "sans", sans)
		extractedSANs[key] = sans
	}

	log.L().Info("--- Prepare (Part 1/3) Complete ---")
	return nil
}
