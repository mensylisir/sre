package stages

import (
	"fmt"
	"go_certs_rotation/config"
	"go_certs_rotation/utils"
	"path/filepath"
)

// ApplyNewCerts executes the apply-new-certs stage.
func ApplyNewCerts(cfg *config.Config) error {
	utils.InfoLogger.Println("====== Starting Stage 2: Apply New Leaf Certs ======")

	hosts, err := loadHosts(cfg.HostsFile)
	if err != nil {
		return err
	}
	ipToHostname, err := getHostnames(hosts, cfg)
	if err != nil {
		return err
	}

	controlPlaneNodes := append(cfg.MasterNodes, cfg.EtcdNodes...)
	controlPlaneNodes = unique(controlPlaneNodes)

	for _, ip := range controlPlaneNodes {
		hostname := ipToHostname[ip]
		utils.InfoLogger.Printf(">>> Processing control plane node: %s (%s)", hostname, ip)
		newDir := filepath.Join(cfg.WorkspaceDir, hostname, "new")

		if contains(cfg.MasterNodes, ip) {
			pkiDir := filepath.Join(newDir, "kubernetes", "pki")
			// Sync all files except CAs
			if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, pkiDir+"/", filepath.Join(cfg.RemotePaths.K8sConfigDir, "pki")+"/"); err != nil {
				return err
			}
		}

		if contains(cfg.EtcdNodes, ip) {
			sslDir := filepath.Join(newDir, "etcd-ssl")
			if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, sslDir+"/", cfg.RemotePaths.EtcdSSLDir+"/"); err != nil {
				return err
			}
		}

		if _, err := utils.RunCommand(ip, cfg.SSH.User, cfg.SSH.Key, "systemctl restart kubelet"); err != nil {
			return err
		}
		// Health checks would go here
	}

	utils.InfoLogger.Println("====== Apply New Certs Stage Completed ======")
	return nil
}

func unique(slice []string) []string {
    keys := make(map[string]bool)
    list := []string{}
    for _, entry := range slice {
        if _, value := keys[entry]; !value {
            keys[entry] = true
            list = append(list, entry)
        }
    }
    return list
}
