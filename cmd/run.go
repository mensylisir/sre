package cmd
import ("go_certs_rotation/pkg/config"; "go_certs_rotation/pkg/log"; "go_certs_rotation/pkg/workflow"; "github.com/spf13/cobra")
var runCmd = &cobra.Command{ Use: "run", Short: "Run the full certificate rotation workflow.", RunE: func(cmd *cobra.Command, args []string) error {
	if err := confirmAction("This will start the full certificate rotation workflow"); err != nil { return err }
	log.L().Info("Loading config", "path", cfgFile); cfg, err := config.LoadConfig(cfgFile); if err != nil { return err }
	wf, err := workflow.NewWorkflow(cfg, dryRun); if err != nil { return err }
	return wf.Run()
}}
func init() { rootCmd.AddCommand(runCmd) }
