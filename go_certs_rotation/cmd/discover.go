package cmd

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/discovery"
	"go_certs_rotation/pkg/k8s"

	"github.com/spf13/cobra"
)

var discoverCmd = &cobra.Command{
	Use:   "discover",
	Short: "Discover and display the cluster topology.",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		clientset, err := k8s.NewClientset(cfg.KubeconfigPath)
		if err != nil {
			return fmt.Errorf("failed to create kubernetes client: %w", err)
		}

		topology, err := discovery.DiscoverTopology(clientset)
		if err != nil {
			return fmt.Errorf("failed to discover topology: %w", err)
		}

		fmt.Println("\nDiscovered Topology:")
		fmt.Println("--------------------")
		fmt.Println("Master Nodes:")
		for _, node := range topology.MasterNodes {
			fmt.Printf("  - Name: %s, IP: %s\n", node.Name, node.InternalIP)
		}
		fmt.Println("\nEtcd Nodes:")
		for _, node := range topology.EtcdNodes {
			fmt.Printf("  - Name: %s, IP: %s\n", node.Name, node.InternalIP)
		}
		fmt.Println("--------------------")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(discoverCmd)
}
