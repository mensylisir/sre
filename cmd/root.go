package cmd
import ("go_certs_rotation/pkg/log"; "os"; "github.com/spf13/cobra")
var (cfgFile string; logLevel string; assumeYes bool; dryRun bool)
var rootCmd = &cobra.Command{ Use: "go-certs-rotation", Short: "A tool for rotating Kubernetes certificates.", PersistentPreRun: func(cmd *cobra.Command, args []string) { log.Init(log.LevelFromString(logLevel)) } }
func Execute() { if err := rootCmd.Execute(); err != nil { log.L().Error("command failed", "error", err); os.Exit(1) } }
func init() {
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "config.yaml", "config file")
	rootCmd.PersistentFlags().StringVar(&logLevel, "log-level", "info", "log level")
	rootCmd.PersistentFlags().BoolVarP(&assumeYes, "yes", "y", false, "auto-confirm all prompts")
	rootCmd.PersistentFlags().BoolVar(&dryRun, "dry-run", false, "simulate changes")
}
