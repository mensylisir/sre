package task

import (
	"fmt"
	"golang.org/x/crypto/ssh"
	"io"
	"io/ioutil"
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
}

// SSHRunner implements the Runner interface using SSH.
type SSHRunner struct {
	client *ssh.Client
}

// NewSSHRunner creates a new SSH task runner.
func NewSSHRunner(host, user, keyPath string) (Runner, error) {
	key, err := ioutil.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("unable to read private key: %w", err)
	}

	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		return nil, fmt.Errorf("unable to parse private key: %w", err)
	}

	config := &ssh.ClientConfig{
		User: user,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(signer),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}

	client, err := ssh.Dial("tcp", host+":22", config)
	if err != nil {
		return nil, fmt.Errorf("unable to connect: %w", err)
	}

	return &SSHRunner{client: client}, nil
}

// Run executes a command on the remote host.
func (r *SSHRunner) Run(cmd string) (string, error) {
	session, err := r.client.NewSession()
	if err != nil {
		return "", fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	output, err := session.CombinedOutput(cmd)
	if err != nil {
		return string(output), fmt.Errorf("failed to run command: %w", err)
	}
	return string(output), nil
}

// Upload copies a file to the remote host using SCP.
func (r *SSHRunner) Upload(srcPath, destPath string) error {
	f, err := os.Open(srcPath)
	if err != nil {
		return fmt.Errorf("failed to open source file: %w", err)
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat source file: %w", err)
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
		return fmt.Errorf("scp failed: %w, output: %s", err, string(output))
	}
	return nil
}

// Download copies a file from the remote host using SCP.
func (r *SSHRunner) Download(srcPath, destPath string) error {
    // Note: This is a simplified SCP download. It expects a single file.
	session, err := r.client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

    // Create a pipe to capture stdout
    stdout, err := session.StdoutPipe()
    if err != nil {
        return fmt.Errorf("failed to create stdout pipe: %w", err)
    }

	// Run scp command
	if err := session.Start(fmt.Sprintf("scp -f %s", srcPath)); err != nil {
		return fmt.Errorf("failed to start scp: %w", err)
	}

    // Read the SCP protocol header
    header := make([]byte, 1024)
    n, err := stdout.Read(header)
    if err != nil {
        return fmt.Errorf("failed to read scp header: %w", err)
    }

    // A simple parser for "C<mode> <size> <filename>"
    parts := strings.Split(string(header[:n]), " ")
    if len(parts) < 3 || !strings.HasPrefix(parts[0], "C") {
        return fmt.Errorf("invalid scp header received")
    }

    // Create the destination file
    f, err := os.Create(destPath)
    if err != nil {
        return fmt.Errorf("failed to create destination file: %w", err)
    }
    defer f.Close()

    // Write the file content
    if _, err := io.Copy(f, stdout); err != nil {
        return fmt.Errorf("failed to write file content: %w", err)
    }

	if err := session.Wait(); err != nil {
		return fmt.Errorf("scp command failed: %w", err)
	}

	return nil
}
