package stages

import (
	"fmt"
	"go_certs_rotation/config"
	"go_certs_rotation/utils"
	"path/filepath"
	"sync"
)

// Rollback executes the rollback stage.
func Rollback(cfg *config.Config) error {
	utils.InfoLogger.Println("====== Starting Stage: Rollback ======")

	hosts, err := loadHosts(cfg.HostsFile)
	if err != nil {
		return err
	}
	ipToHostname, err := getHostnames(hosts, cfg)
	if err != nil {
		return err
	}

	var wg sync.WaitGroup
	errChan := make(chan error, len(hosts))

	for _, ip := range hosts {
		wg.Add(1)
		go func(ip string) {
			defer wg.Done()
			hostname := ipToHostname[ip]
			utils.InfoLogger.Printf(">>> Rolling back node: %s (%s)", hostname, ip)
			oldDir := filepath.Join(cfg.WorkspaceDir, hostname, "old")

			if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(oldDir, "kubelet.conf"), cfg.RemotePaths.KubeletConf); err != nil {
				errChan <- err
				return
			}
			if contains(cfg.MasterNodes, ip) {
				if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(oldDir, "kubernetes")+"/", cfg.RemotePaths.K8sConfigDir+"/"); err != nil {
					errChan <- err
					return
				}
			}
			if contains(cfg.EtcdNodes, ip) {
				if err := utils.SyncToRemote(ip, cfg.SSH.User, cfg.SSH.Key, filepath.Join(oldDir, "etcd-ssl")+"/", cfg.RemotePaths.EtcdSSLDir+"/"); err != nil {
					errChan <- err
					return
				}
			}
			if _, err := utils.RunCommand(ip, cfg.SSH.User, cfg.SSH.Key, "systemctl restart kubelet"); err != nil {
				errChan <- err
				return
			}
		}(ip)
	}

	wg.Wait()
	close(errChan)

	for err := range errChan {
		utils.ErrorLogger.Println(err)
	}
    if len(errChan) > 0 {
        return fmt.Errorf("rollback failed for one or more nodes")
    }


	utils.InfoLogger.Println("====== Rollback Stage Completed ======")
	return nil
}
