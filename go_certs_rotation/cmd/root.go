package cmd

import (
	"go_certs_rotation/pkg/log"
	"os"

	"github.com/spf13/cobra"
)

var (
	cfgFile   string
	logLevel  string
	dryRun    bool
)

var rootCmd = &cobra.Command{
	Use:   "go-certs-rotation",
	Short: "A tool for intelligently rotating Kubernetes certificates.",
	Long: `go-certs-rotation is a CLI tool that automates the process of
rotating CA and leaf certificates in a Kubernetes cluster with zero downtime.`,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		level := log.LevelFromString(logLevel)
		log.Init(level)
	},
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		log.L().Error("command failed", "error", err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "config.yaml", "config file (default is config.yaml)")
	rootCmd.PersistentFlags().StringVar(&logLevel, "log-level", "info", "log level (debug, info, warn, error)")
	rootCmd.PersistentFlags().BoolVar(&dryRun, "dry-run", false, "Simulate the command without making any actual changes.")
}
