package cmd

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/workflow"

	"github.com/spf13/cobra"
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run the full certificate rotation workflow.",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		wf, err := workflow.NewWorkflow(cfg)
		if err != nil {
			return fmt.Errorf("failed to initialize workflow: %w", err)
		}

		if err := wf.Run(); err != nil {
			return fmt.Errorf("workflow execution failed: %w", err)
		}

        fmt.Println("Certificate rotation workflow completed successfully!")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(runCmd)
}
