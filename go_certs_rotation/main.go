package main

import (
	"fmt"
	"log"
	"os"

	"go_certs_rotation/stages"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go_certs_rotation <stage>")
		os.Exit(1)
	}

	stage := os.Args[1]

	ctx := stages.StageContext{
		SSHUser:     os.Getenv("SSH_USER"),
		SSHKey:      os.Getenv("SSH_KEY"),
		RemoteHost:  os.Getenv("REMOTE_HOST"),
		Workspace:   "workspace",
		CertsPath:   "workspace/leaf.crt",
		RemotePath:  "/tmp/leaf.crt",
	}

	switch stage {
	case "prepare":
		if err := ctx.PrepareStage(); err != nil {
			log.Fatalf("Prepare stage failed: %v", err)
		}
	case "apply-bundle":
		if err := ctx.ApplyBundleStage(); err != nil {
			log.Fatalf("Apply bundle stage failed: %v", err)
		}
	case "apply-new-certs":
		if err := ctx.ApplyNewCertsStage(); err != nil {
			log.Fatalf("Apply new certs stage failed: %v", err)
		}
	case "apply-final-config":
		if err := ctx.ApplyFinalConfigStage(); err != nil {
			log.Fatalf("Apply final config stage failed: %v", err)
		}
	case "rollback":
		if err := ctx.RollbackStage(); err != nil {
			log.Fatalf("Rollback stage failed: %v", err)
		}
	default:
		fmt.Println("Unknown stage:", stage)
		os.Exit(1)
	}

	fmt.Printf("Stage '%s' completed successfully.\n", stage)
}
