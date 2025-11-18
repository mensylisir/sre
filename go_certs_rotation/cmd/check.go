package cmd

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/discovery"
	"go_certs_rotation/pkg/k8s"
	"go_certs_rotation/pkg/log"
	"go_certs_rotation/pkg/task"
	"sync"

	"github.com/spf13/cobra"
)

var checkCmd = &cobra.Command{
	Use:   "check",
	Short: "Perform pre-flight checks to verify configuration and connectivity.",
	Long: `This command runs a series of checks to ensure the tool can connect to the
Kubernetes API and all the discovered nodes via SSH. It's a safe, read-only
operation that should be run before executing the 'run' command.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		log.L().Info("--- Running Pre-flight Checks ---")

		// 1. Load Configuration
		log.L().Info("[1/4] Loading configuration", "path", cfgFile)
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			return fmt.Errorf("configuration loading failed: %w", err)
		}
		log.L().Info("✓ Configuration loaded successfully.")

		// 2. Connect to Kubernetes API
		log.L().Info("[2/4] Connecting to Kubernetes API...")
		clientset, err := k8s.NewClientset(cfg.KubeconfigPath)
		if err != nil {
			return fmt.Errorf("Kubernetes API connection failed: %w", err)
		}
		serverVersion, err := clientset.Discovery().ServerVersion()
		if err != nil {
			return fmt.Errorf("could not get server version: %w", err)
		}
		log.L().Info("✓ Connected to Kubernetes API", "version", serverVersion.GitVersion)

		// 3. Discover Cluster Topology
		log.L().Info("[3/4] Discovering cluster topology...")
		topology, err := discovery.DiscoverTopology(clientset)
		if err != nil {
			return fmt.Errorf("topology discovery failed: %w", err)
		}
		log.L().Info("✓ Topology discovered successfully.")
		for _, node := range topology.MasterNodes {
			log.L().Info("  - Found master node", "name", node.Name, "ip", node.InternalIP)
		}
		for _, node := range topology.EtcdNodes {
			log.L().Info("  - Found etcd node", "name", node.Name, "ip", node.InternalIP)
		}

		// 4. Test SSH Connectivity to all nodes
		log.L().Info("[4/4] Testing SSH connectivity to all discovered nodes...")
		allNodes := append(topology.MasterNodes, topology.EtcdNodes...)
		nodeMap := make(map[string]discovery.Node)
		for _, node := range allNodes {
			nodeMap[node.Name] = node
		}

		var wg sync.WaitGroup
		errChan := make(chan error, len(nodeMap))
		for _, node := range nodeMap {
			wg.Add(1)
			go func(n discovery.Node) {
				defer wg.Done()
				log.L().Debug("Checking connection", "node", n.Name, "ip", n.InternalIP)
				runner, err := task.NewSSHRunner(n.InternalIP, cfg.SSH.User, cfg.SSH.KeyPath)
				if err != nil {
					errChan <- fmt.Errorf("failed to connect to %s: %w", n.Name, err)
					return
				}
				defer runner.Close()
				if _, err := runner.Run("hostname"); err != nil {
					errChan <- fmt.Errorf("failed to run command on %s: %w", n.Name, err)
					return
				}
			}(node)
		}

		wg.Wait()
		close(errChan)

		if len(errChan) > 0 {
			for e := range errChan {
				log.L().Error("SSH connectivity check failed", "error", e)
			}
			return fmt.Errorf("pre-flight checks failed")
		}
		log.L().Info("✓ SSH connectivity to all nodes successful.")

		log.L().Info("--- Pre-flight Checks Passed ---")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(checkCmd)
}
