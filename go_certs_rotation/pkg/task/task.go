package task

// Runner is an interface for running remote tasks.
type Runner interface {
	Run(cmd string) (string, error)
	Upload(src, dest string) error
	Download(src, dest string) error
}

// NewSSHRunner creates a new SSH task runner.
func NewSSHRunner(host, user, keyPath string) Runner {
	// TODO: Implement SSH runner.
	return nil
}
