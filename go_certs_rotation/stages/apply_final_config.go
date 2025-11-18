package stages

import (
	"fmt"
	"go_certs_rotation/config"
	"go_certs_rotation/utils"
	"path/filepath"
)

// ApplyFinalConfig executes the apply-final-config stage.
func ApplyFinalConfig(cfg *config.Config) error {
	utils.InfoLogger.Println("====== Starting Stage 3: Apply Final Config ======")

	hosts, err := loadHosts(cfg.HostsFile)
	if err != nil {
		return err
	}
	ipToHostname, err := getHostnames(hosts, cfg)
	if err != nil {
		return err
	}

    // This logic is very similar to ApplyBundle, but using the 'new' directory
    // instead of 'bundle'. A refactor could merge these.

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
		newDir := filepath.Join(cfg.WorkspaceDir, hostname, "new")

		if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(newDir, "kubelet.conf"), cfg.RemotePaths.KubeletConf); err != nil {
			return err
		}
		if _, err := utils.RunCommand(ip, cfg.SSH.User, cfg.SSH.Key, "systemctl restart kubelet"); err != nil {
			return err
		}
		// Health checks
	}

	// Update master nodes
	for _, ip := range cfg.MasterNodes {
		hostname := ipToHostname[ip]
		utils.InfoLogger.Printf(">>> Processing Master node: %s (%s)", hostname, ip)
		newDir := filepath.Join(cfg.WorkspaceDir, hostname, "new")

        if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(newDir, "kubernetes") + "/", cfg.RemotePaths.K8sConfigDir + "/"); err != nil {
            return err
        }
        if contains(cfg.EtcdNodes, ip) {
             if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(newDir, "etcd-ssl") + "/", cfg.RemotePaths.EtcdSSLDir + "/"); err != nil {
                return err
            }
        }
		if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(newDir, "kubelet.conf"), cfg.RemotePaths.KubeletConf); err != nil {
			return err
		}
		if _, err := utils.RunCommand(ip, cfg.SSH.User, cfg.SSH.Key, "systemctl restart kubelet"); err != nil {
			return err
		}
		// Health checks
	}

	utils.InfoLogger.Println("====== Apply Final Config Stage Completed ======")
	return nil
}
