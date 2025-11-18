package task

import (
	"fmt"
	"go_certs_rotation/pkg/log"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
	"io"
	"io/ioutil"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Runner provides an interface for running remote tasks.
type Runner interface {
	Run(cmd string) (string, error)
	Upload(srcPath, destPath string) error
	Download(srcPath, destPath string) error
	Close()
}

// ... (SSHRunner implementation remains the same)

// DryRunRunner is a mock runner for --dry-run mode.
type DryRunRunner struct {
	Host string
}

func (r *DryRunRunner) Run(cmd string) (string, error) {
	log.L().Info("[DRY-RUN] Would run command", "host", r.Host, "command", cmd)
	return fmt.Sprintf("hostname-of-%s", r.Host), nil // Return a predictable mock value
}

func (r *DryRunRunner) Upload(srcPath, destPath string) error {
	log.L().Info("[DRY-RUN] Would upload file", "host", r.Host, "source", srcPath, "destination", destPath)
	return nil
}

func (r *DryRunRunner) Download(srcPath, destPath string) error {
	log.L().Info("[DRY-RUN] Would download file", "host", r.Host, "source", srcPath, "destination", destPath)
	// Create a dummy file to allow the workflow to proceed
	return ioutil.WriteFile(destPath, []byte("dummy content"), 0644)
}

func (r *DryRunRunner) Close() {
	// No-op for dry run
}
