package cmd

import (
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/log"
	"go_certs_rotation/pkg/workflow"

	"github.com/spf13/cobra"
)

var rollbackCmd = &cobra.Command{
	Use:   "rollback",
	Short: "Roll back certificates to the backed-up state.",
	RunE: func(cmd *cobra.Command, args []string) error {
		log.L().Info("Loading configuration", "path", cfgFile)
		cfg, err := config.LoadConfig(cfgFile)
		if err != nil {
			return err
		}

		wf, err := workflow.NewWorkflow(cfg, dryRun)
		if err != nil {
			return err
		}

		if err := wf.Rollback(); err != nil {
			return err
		}

        log.L().Info("Certificate rollback completed successfully!")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(rollbackCmd)
}
