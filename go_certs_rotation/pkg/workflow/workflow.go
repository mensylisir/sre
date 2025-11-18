package workflow
import ("go_certs_rotation/pkg/config"; "go_certs_rotation/pkg/discovery"; "go_certs_rotation/pkg/k8s"; "k8s.io/client-go/kubernetes")
type Workflow struct {
	config *config.Config
	topology *discovery.ClusterTopology
	clientset *kubernetes.Clientset
	dryRun bool
}
func NewWorkflow(cfg *config.Config, dryRun bool) (*Workflow, error) {
	clientset, err := k8s.NewClientset(cfg.KubeconfigPath)
	if err != nil { return nil, err }
	topology, err := discovery.DiscoverTopology(clientset)
	if err != nil { return nil, err }
	return &Workflow{config: cfg, topology: topology, clientset: clientset, dryRun: dryRun}, nil
}
func (w *Workflow) Run() error { if err := w.Prepare(); err != nil { return err }; return w.Rotate() }
func (w *Workflow) Rollback() error { /* ... */ return nil }
