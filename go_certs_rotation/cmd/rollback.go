package cmd

import (
	"fmt"
	// "go_certs_rotation/pkg/config"
	// "go_certs_rotation/pkg/workflow"
	"github.com/spf13/cobra"
)

var rollbackCmd = &cobra.Command{
	Use:   "rollback",
	Short: "Roll back certificates to the backed-up state.",
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := confirmAction("You are about to start the rollback procedure. This will revert certificates and restart components."); err != nil {
			return err
		}

		fmt.Println("Proceeding with rollback workflow...")
		// cfg, err := config.LoadConfig(cfgFile)
		// ...
		// wf, err := workflow.NewWorkflow(cfg, false)
		// ...
		// if err := wf.Rollback(); err != nil { ... }

		return nil
	},
}

func init() {
	rootCmd.AddCommand(rollbackCmd)
}
