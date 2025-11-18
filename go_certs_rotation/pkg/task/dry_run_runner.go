package task

import (
	"fmt"
	"io/ioutil"
)

// DryRunRunner is a mock runner for --dry-run mode.
type DryRunRunner struct {
	Host string
}

func (r *DryRunRunner) Run(cmd string) (string, error) {
	fmt.Printf("[DRY-RUN] Would run command on %s: %s\n", r.Host, cmd)
	// Return a predictable mock value for commands that expect output (like hostname)
	if cmd == "hostname" {
		return fmt.Sprintf("dry-run-host-of-%s", r.Host), nil
	}
	return "", nil
}

func (r *DryRunRunner) Upload(srcPath, destPath string) error {
	fmt.Printf("[DRY-RUN] Would upload file from %s to %s:%s\n", srcPath, r.Host, destPath)
	return nil
}

func (r *DryRunRunner) Download(srcPath, destPath string) error {
	fmt.Printf("[DRY-RUN] Would download file from %s:%s to %s\n", r.Host, srcPath, destPath)
	// Create a dummy file to allow the workflow to proceed, as some steps
	// might try to read the downloaded file (e.g., to extract SANs).
	return ioutil.WriteFile(destPath, []byte("dry-run dummy content"), 0644)
}

func (r *DryRunRunner) Close() {
	// No-op for dry run
}
