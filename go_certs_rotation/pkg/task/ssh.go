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

// NewRunner returns a real SSH runner or a dry-run runner based on the flag.
func NewRunner(dryRun bool, host, user, keyPath string) (Runner, error) {
	if dryRun {
		return &DryRunRunner{Host: host}, nil
	}
	return newSSHRunner(host, user, keyPath)
}

// SSHRunner implements the Runner interface using SSH.
type SSHRunner struct {
	client *ssh.Client
}

// newSSHRunner creates a new SSH task runner.
func newSSHRunner(host, user, keyPath string) (Runner, error) {
	var authMethods []ssh.AuthMethod

	if sshAgentConn, err := net.Dial("unix", os.Getenv("SSH_AUTH_SOCK")); err == nil {
		agentClient := agent.NewClient(sshAgentConn)
		signers, err := agentClient.Signers()
		if err == nil {
			authMethods = append(authMethods, ssh.PublicKeys(signers...))
		}
	}

	if keyPath != "" {
		key, err := ioutil.ReadFile(keyPath)
		if err != nil { return nil, err }
		signer, err := ssh.ParsePrivateKey(key)
		if err != nil { return nil, err }
		authMethods = append(authMethods, ssh.PublicKeys(signer))
	}

	if len(authMethods) == 0 {
		return nil, fmt.Errorf("no SSH authentication method available")
	}

	config := &ssh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}

	client, err := ssh.Dial("tcp", host+":22", config)
	if err != nil {
		return nil, err
	}

	return &SSHRunner{client: client}, nil
}

// ... (Rest of SSHRunner and DryRunRunner methods)
// ...
func (r *SSHRunner) Close() {
	r.client.Close()
}

func (r *SSHRunner) Run(cmd string) (string, error) {
	session, err := r.client.NewSession()
	if err != nil {
		return "", fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	output, err := session.CombinedOutput(cmd)
	if err != nil {
		return string(output), fmt.Errorf("failed to run command '%s': %w", cmd, err)
	}
	return string(output), nil
}

func (r *SSHRunner) Upload(srcPath, destPath string) error {
	f, err := os.Open(srcPath)
	if err != nil {
		return fmt.Errorf("failed to open source file '%s': %w", srcPath, err)
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat source file '%s': %w", srcPath, err)
	}

	session, err := r.client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	go func() {
		w, _ := session.StdinPipe()
		defer w.Close()
		fmt.Fprintf(w, "C%#o %d %s\n", stat.Mode().Perm(), stat.Size(), filepath.Base(destPath))
		io.Copy(w, f)
		fmt.Fprint(w, "\x00")
	}()

	cmd := fmt.Sprintf("scp -t %s", filepath.Dir(destPath))
	if output, err := session.CombinedOutput(cmd); err != nil {
		return fmt.Errorf("scp upload failed: %w, output: %s", err, string(output))
	}
	return nil
}

func (r *SSHRunner) Download(srcPath, destPath string) error {
	session, err := r.client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	cmd := fmt.Sprintf("scp -f %s", srcPath)

	stdout, err := session.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to create stdout pipe: %w", err)
	}
	stdin, err := session.StdinPipe()
	if err != nil {
		return fmt.Errorf("failed to create stdin pipe: %w", err)
	}

	if err := session.Start(cmd); err != nil {
		return fmt.Errorf("failed to start scp session: %w", err)
	}

	stdin.Write([]byte{0})

	if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
		return fmt.Errorf("failed to create destination directory '%s': %w", destPath, err)
	}

	f, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("failed to create destination file '%s': %w", destPath, err)
	}
	defer f.Close()

	headerBuf := make([]byte, 1024)
	n, err := stdout.Read(headerBuf)
	if err != nil {
		return fmt.Errorf("failed to read scp header: %w", err)
	}
	header := string(headerBuf[:n])

	if strings.HasPrefix(header, "C") {
		_, err = io.Copy(f, stdout)
		if err != nil {
			return fmt.Errorf("failed to write file content: %w", err)
		}
	} else if strings.HasPrefix(header, "\x01") {
		return fmt.Errorf("scp download error from server: %s", header[1:])
	} else {
		return fmt.Errorf("unexpected scp header: %s", header)
	}

	stdin.Write([]byte{0})

	if err := session.Wait(); err != nil {
		return fmt.Errorf("scp command wait failed: %w", err)
	}

	return nil
}


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
