package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/discovery"
	"go_certs_rotation/pkg/k8s"
	"go_certs_rotation/pkg/log"
	"path/filepath"

	"k8s.io/client-go/kubernetes"
)

// Workflow holds the state for the certificate rotation process.
type Workflow struct {
	config    *config.Config
	clientset *kubernetes.Clientset
	topology  *discovery.ClusterTopology
	dryRun    bool
	workspace struct {
		localBackupDir   string
		localNewCertsDir string
	}
}

// NewWorkflow creates a new workflow instance.
func NewWorkflow(cfg *config.Config, dryRun bool) (*Workflow, error) {
	log.L().Info("Initializing new workflow...", "dryRun", dryRun)
	clientset, err := k8s.NewClientset(cfg.KubeconfigPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create kubernetes clientset: %w", err)
	}

	topology, err := discovery.DiscoverTopology(clientset)
	if err != nil {
		return nil, fmt.Errorf("failed to discover cluster topology: %w", err)
	}

	return &Workflow{
		config:    cfg,
		clientset: clientset,
		topology:  topology,
		dryRun:    dryRun,
		workspace: struct {
			localBackupDir   string
			localNewCertsDir string
		}{
			localBackupDir:   filepath.Join(cfg.Workspace, "backup"),
			localNewCertsDir: filepath.Join(cfg.Workspace, "new_certs"),
		},
	}, nil
}

// Run executes the full certificate rotation workflow.
func (w *Workflow) Run() error {
	if err := w.Prepare(); err != nil {
		return fmt.Errorf("prepare phase failed: %w", err)
	}
	if err := w.Rotate(); err != nil {
		return fmt.Errorf("rotation phase failed: %w", err)
	}
	return nil
}
