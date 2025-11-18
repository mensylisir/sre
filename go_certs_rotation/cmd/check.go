package cmd

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/discovery"
	"go_certs_rotation/pkg/k8s"
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
		fmt.Println("--- Running Pre-flight Checks ---")

		// 1. Load Configuration
		fmt.Println("\n[1/4] Loading configuration from", cfgFile, "...")
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			return fmt.Errorf("✗ Configuration loading failed: %w", err)
		}
		fmt.Println("✓ Configuration loaded successfully.")

		// 2. Connect to Kubernetes API
		fmt.Println("\n[2/4] Connecting to Kubernetes API...")
		clientset, err := k8s.NewClientset(cfg.KubeconfigPath)
		if err != nil {
			return fmt.Errorf("✗ Kubernetes API connection failed: %w", err)
		}
		serverVersion, err := clientset.Discovery().ServerVersion()
		if err != nil {
			return fmt.Errorf("✗ Could not get server version: %w", err)
		}
		fmt.Printf("✓ Connected to Kubernetes API server version %s\n", serverVersion.GitVersion)

		// 3. Discover Cluster Topology
		fmt.Println("\n[3/4] Discovering cluster topology...")
		topology, err := discovery.DiscoverTopology(clientset)
		if err != nil {
			return fmt.Errorf("✗ Topology discovery failed: %w", err)
		}
		fmt.Println("✓ Topology discovered successfully:")
		fmt.Println("  Master Nodes:")
		for _, node := range topology.MasterNodes {
			fmt.Printf("    - %s (%s)\n", node.Name, node.InternalIP)
		}
		fmt.Println("  Etcd Nodes:")
		for _, node := range topology.EtcdNodes {
			fmt.Printf("    - %s (%s)\n", node.Name, node.InternalIP)
		}

		// 4. Test SSH Connectivity to all nodes
		fmt.Println("\n[4/4] Testing SSH connectivity to all discovered nodes...")
		allNodes := append(topology.MasterNodes, topology.EtcdNodes...)
		// Deduplicate nodes
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
				fmt.Printf("  - Checking connection to %s (%s)...\n", n.Name, n.InternalIP)
				runner, err := task.NewSSHRunner(n.InternalIP, cfg.SSH.User, cfg.SSH.KeyPath)
				if err != nil {
					errChan <- fmt.Errorf("✗ Failed to connect to %s: %w", n.Name, err)
					return
				}
				defer runner.Close()
				// Run a simple command to verify
				if _, err := runner.Run("hostname"); err != nil {
					errChan <- fmt.Errorf("✗ Failed to run command on %s: %w", n.Name, err)
					return
				}
			}(node)
		}

		wg.Wait()
		close(errChan)

		if len(errChan) > 0 {
			fmt.Println("\nSSH connectivity check failed for one or more nodes:")
			for e := range errChan {
				fmt.Println(e)
			}
			return fmt.Errorf("pre-flight checks failed")
		}
		fmt.Println("✓ SSH connectivity to all nodes successful.")

		fmt.Println("\n--- Pre-flight Checks Passed ---")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(checkCmd)
}
