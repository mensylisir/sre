package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	cfgFile string
)

var rootCmd = &cobra.Command{
	Use:   "go-certs-rotation",
	Short: "A tool for intelligently rotating Kubernetes certificates.",
	Long: `go-certs-rotation is a CLI tool that automates the process of
rotating CA and leaf certificates in a Kubernetes cluster with zero downtime.`,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "config.yaml", "config file (default is config.yaml)")
}
