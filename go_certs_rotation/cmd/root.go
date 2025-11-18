package cmd

import (
	"fmt"
	// "go_certs_rotation/pkg/log"
	"os"
	"github.com/spf13/cobra"
)

var (
	cfgFile   string
	logLevel  string
	assumeYes bool
	dryRun    bool
)

var rootCmd = &cobra.Command{
	Use:   "go-certs-rotation",
	Short: "A tool for intelligently rotating Kubernetes certificates.",
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		// Init logger
	},
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "config.yaml", "config file")
	rootCmd.PersistentFlags().StringVar(&logLevel, "log-level", "info", "log level (debug, info, warn, error)")
	rootCmd.PersistentFlags().BoolVarP(&assumeYes, "yes", "y", false, "Automatically answer yes to all prompts")
	rootCmd.PersistentFlags().BoolVar(&dryRun, "dry-run", false, "Simulate the command without making any actual changes")
}
