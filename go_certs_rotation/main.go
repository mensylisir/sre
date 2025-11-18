package main

import (
	"flag"
	"fmt"
	"go_certs_rotation/config"
	"go_certs_rotation/stages"
	"go_certs_rotation/utils"
	"os"
)

func main() {
	configPath := flag.String("config", "config.yaml", "Path to the configuration file.")
	stage := flag.String("stage", "", "The stage to execute (prepare, apply-bundle, apply-new-certs, apply-final-config, rollback).")
	flag.Parse()

	if *stage == "" {
		utils.ErrorLogger.Println("Error: --stage flag is required.")
		flag.Usage()
		os.Exit(1)
	}

	cfg, err := config.LoadConfig(*configPath)
	if err != nil {
		utils.ErrorLogger.Fatalf("Failed to load config: %v", err)
	}

	switch *stage {
	case "prepare":
		err = stages.Prepare(cfg)
	case "apply-bundle":
		err = stages.ApplyBundle(cfg)
	case "apply-new-certs":
		err = stages.ApplyNewCerts(cfg)
	case "apply-final-config":
		err = stages.ApplyFinalConfig(cfg)
	case "rollback":
		err = stages.Rollback(cfg)
	default:
		utils.ErrorLogger.Fatalf("Unknown stage: %s", *stage)
	}

	if err != nil {
		utils.ErrorLogger.Fatalf("Stage '%s' failed: %v", *stage, err)
	}

	utils.InfoLogger.Printf("Stage '%s' completed successfully.", *stage)
}
