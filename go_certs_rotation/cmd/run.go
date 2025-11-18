package cmd

import (
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/log"
	"go_certs_rotation/pkg/workflow"

	"github.com/spf13/cobra"
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run the full certificate rotation workflow.",
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

		if err := wf.Run(); err != nil {
			return err
		}

        log.L().Info("Certificate rotation workflow completed successfully!")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(runCmd)
}
