package cmd

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/workflow"

	"github.com/spf13/cobra"
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run the certificate rotation workflow.",
	Long:  `This command starts the main workflow to rotate certificates.`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("Loading configuration from", cfgFile)
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			fmt.Println("Error loading config:", err)
			return
		}

		if err := workflow.Run(cfg); err != nil {
			fmt.Println("Workflow failed:", err)
		}
	},
}

func init() {
	rootCmd.AddCommand(runCmd)
}
