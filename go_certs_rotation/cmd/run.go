package cmd

import (
	"fmt"
	// "go_certs_rotation/pkg/config"
	// "go_certs_rotation/pkg/workflow"
	"github.com/spf13/cobra"
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run the full certificate rotation workflow.",
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := confirmAction("You are about to start the certificate rotation workflow. This will restart cluster components."); err != nil {
			return err
		}

		fmt.Println("Proceeding with rotation workflow...")
		// cfg, err := config.LoadConfig(cfgFile)
		// ...
		// wf, err := workflow.NewWorkflow(cfg, false)
		// ...
		// if err := wf.Run(); err != nil { ... }

		return nil
	},
}

func init() {
	rootCmd.AddCommand(runCmd)
}
