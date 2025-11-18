package workflow

import (
	// "go_certs_rotation/pkg/config"
	// "go_certs_rotation/pkg/discovery"
	// "go_certs_rotation/pkg/k8s"
)

type Workflow struct {
	// ... other fields
	dryRun bool
}

// func NewWorkflow(cfg *config.Config, dryRun bool) (*Workflow, error) {
// 	// ...
// 	return &Workflow{
// 		// ...
// 		dryRun: dryRun,
// 	}, nil
// }

func (w *Workflow) Prepare() error {
	// ... inside prepare ...
	// runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
	// ...
	return nil
}

func (w *Workflow) Rotate() error {
	// ... inside rotate ...
	// runner, err := task.NewRunner(w.dryRun, node.InternalIP, w.config.SSH.User, w.config.SSH.KeyPath)
	// ...
	// if !w.dryRun {
	// 	k8s.WaitForNodeReady(...)
	// }
	// ...
	return nil
}
