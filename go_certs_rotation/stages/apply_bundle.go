package stages

import (
	"fmt"
	"go_certs_rotation/config"
	"go_certs_rotation/utils"
	"path/filepath"
)

// ApplyBundle executes the apply-bundle stage.
func ApplyBundle(cfg *config.Config) error {
	utils.InfoLogger.Println("====== Starting Stage 1: Apply Bundle Config ======")

	hosts, err := loadHosts(cfg.HostsFile)
	if err != nil {
		return err
	}
	ipToHostname, err := getHostnames(hosts, cfg)
	if err != nil {
		return err
	}

	// Get worker nodes
	var workerNodes []string
	for _, ip := range hosts {
		if !contains(cfg.MasterNodes, ip) {
			workerNodes = append(workerNodes, ip)
		}
	}

	// Update worker nodes
	for _, ip := range workerNodes {
		hostname := ipToHostname[ip]
		utils.InfoLogger.Printf(">>> Processing Worker node: %s (%s)", hostname, ip)
		bundleDir := filepath.Join(cfg.WorkspaceDir, hostname, "bundle")

		if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(bundleDir, "kubelet.conf"), cfg.RemotePaths.KubeletConf); err != nil {
			return err
		}
		// Also sync CA cert for good measure
		if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(cfg.WorkspaceDir, "k8s-bundle.crt"), filepath.Join(cfg.RemotePaths.K8sConfigDir, "pki", "ca.crt")); err != nil {
            return err
        }

		if _, err := utils.RunCommand(ip, cfg.SSH.User, cfg.SSH.Key, "systemctl restart kubelet"); err != nil {
			return err
		}
		// In a real scenario, we would add a health check here.
	}

	// Update master nodes
	for _, ip := range cfg.MasterNodes {
		hostname := ipToHostname[ip]
		utils.InfoLogger.Printf(">>> Processing Master node: %s (%s)", hostname, ip)
		bundleDir := filepath.Join(cfg.WorkspaceDir, hostname, "bundle")

        // Sync all k8s configs
        if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(bundleDir, "kubernetes") + "/", cfg.RemotePaths.K8sConfigDir + "/"); err != nil {
            return err
        }

        // Sync etcd CA
        if contains(cfg.EtcdNodes, ip) {
             if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(bundleDir, "etcd-ssl") + "/", cfg.RemotePaths.EtcdSSLDir + "/"); err != nil {
                return err
            }
        } else {
             if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(cfg.WorkspaceDir, "etcd-bundle.pem"), filepath.Join(cfg.RemotePaths.EtcdSSLDir, "ca.pem")); err != nil {
                return err
            }
        }

		if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(bundleDir, "kubelet.conf"), cfg.RemotePaths.KubeletConf); err != nil {
			return err
		}
		if _, err := utils.RunCommand(ip, cfg.SSH.User, cfg.SSH.Key, "systemctl restart kubelet"); err != nil {
			return err
		}
		// In a real scenario, we would add a health check here.
	}

	utils.InfoLogger.Println("====== Apply Bundle Stage Completed ======")
	return nil
}
