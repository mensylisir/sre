package cmd

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/workflow"

	"github.com/spf13/cobra"
)

var rollbackCmd = &cobra.Command{
	Use:   "rollback",
	Short: "Roll back the certificate rotation.",
	Long:  `This command starts the workflow to roll back certificates to their previous state.`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("Loading configuration from", cfgFile)
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			fmt.Println("Error loading config:", err)
			return
		}

		if err := workflow.Rollback(cfg); err != nil {
			fmt.Println("Rollback workflow failed:", err)
		}
	},
}

func init() {
	rootCmd.AddCommand(rollbackCmd)
}
