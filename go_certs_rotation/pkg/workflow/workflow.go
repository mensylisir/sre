package workflow

import (
	"fmt"
	"go_certs_rotation/pkg/config"
	"go_certs_rotation/pkg/discovery"
	"go_certs_rotation/pkg/k8s"
	"k8s.io/client-go/kubernetes"
)

// Workflow holds the state for the certificate rotation process.
type Workflow struct {
	config    *config.Config
	topology  *discovery.ClusterTopology
	clientset *kubernetes.Clientset
	dryRun    bool
}

// NewWorkflow creates a new workflow instance.
func NewWorkflow(cfg *config.Config, dryRun bool) (*Workflow, error) {
	clientset, err := k8s.NewClientset(cfg.KubeconfigPath)
	if err != nil { return nil, err }
	topology, err := discovery.DiscoverTopology(clientset)
	if err != nil { return nil, err }
	return &Workflow{config: cfg, topology: topology, clientset: clientset, dryRun: dryRun}, nil
}

// Prepare runs all three parts of the preparation phase.
func (w *Workflow) Prepare() error {
	if err := w.preparePart1_BackupAndExtractSANs(); err != nil {
		return fmt.Errorf("prepare part 1 (backup & SANs extraction) failed: %w", err)
	}
	if err := w.preparePart2_GenerateCerts(); err != nil {
		return fmt.Errorf("prepare part 2 (certificate generation) failed: %w", err)
	}
	if err := w.preparePart3_BundleAndUpdateConfigs(); err != nil {
		return fmt.Errorf("prepare part 3 (bundling & config update) failed: %w", err)
	}
	return nil
}

func (w *Workflow) Rotate() error { /* ... */ return nil }
func (w *Workflow) Rollback() error { /* ... */ return nil }
