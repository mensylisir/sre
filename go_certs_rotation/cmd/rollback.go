package cmd

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/workflow"

	"github.com/spf13/cobra"
)

var rollbackCmd = &cobra.Command{
	Use:   "rollback",
	Short: "Roll back certificates to the backed-up state.",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		wf, err := workflow.NewWorkflow(cfg)
		if err != nil {
			return fmt.Errorf("failed to initialize workflow: %w", err)
		}

		if err := wf.Rollback(); err != nil {
			return fmt.Errorf("rollback execution failed: %w", err)
		}

        fmt.Println("Certificate rollback completed successfully!")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(rollbackCmd)
}
