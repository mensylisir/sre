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
	Short: "Discover the cluster topology.",
	Long:  `This command connects to the Kubernetes cluster, discovers the control-plane and etcd nodes, and prints the topology.`,
	Run: func(cmd *cobra.command, args []string) {
		fmt.Println("Loading configuration from", cfgFile)
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			fmt.Println("Error loading config:", err)
			return
		}

		clientset, err := k8s.NewClientset(cfg.KubeconfigPath)
		if err != nil {
			fmt.Println("Error creating Kubernetes client:", err)
			return
		}

		fmt.Println("Discovering cluster topology...")
		topology, err := discovery.DiscoverTopology(clientset)
		if err != nil {
			fmt.Println("Error discovering topology:", err)
			return
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
	},
}

func init() {
	rootCmd.AddCommand(discoverCmd)
}
