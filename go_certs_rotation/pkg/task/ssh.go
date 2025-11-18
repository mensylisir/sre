package task

import (
	"fmt"
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

// SSHRunner implements the Runner interface using SSH.
type SSHRunner struct {
	client *ssh.Client
}

// NewSSHRunner creates a new SSH task runner, supporting both private key and SSH agent authentication.
func NewSSHRunner(host, user, keyPath string) (Runner, error) {
	var authMethods []ssh.AuthMethod

	// 1. Try to use SSH Agent authentication if available
	if sshAgentConn, err := net.Dial("unix", os.Getenv("SSH_AUTH_SOCK")); err == nil {
		agentClient := agent.NewClient(sshAgentConn)
		signers, err := agentClient.Signers()
		if err == nil {
			authMethods = append(authMethods, ssh.PublicKeys(signers...))
			fmt.Printf("  - SSH Agent found, adding as authentication method.\n")
		}
	}

	// 2. Use private key authentication if a key path is provided
	if keyPath != "" {
		key, err := ioutil.ReadFile(keyPath)
		if err != nil {
			return nil, fmt.Errorf("unable to read private key: %w", err)
		}
		signer, err := ssh.ParsePrivateKey(key)
		if err != nil {
			return nil, fmt.Errorf("unable to parse private key: %w", err)
		}
		authMethods = append(authMethods, ssh.PublicKeys(signer))
		fmt.Printf("  - Using private key %s as authentication method.\n", keyPath)
	}

	if len(authMethods) == 0 {
		return nil, fmt.Errorf("no SSH authentication method available; please provide a key path or run an SSH agent")
	}

	config := &ssh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}

	client, err := ssh.Dial("tcp", host+":22", config)
	if err != nil {
		return nil, fmt.Errorf("unable to connect to %s: %w", host, err)
	}

	return &SSHRunner{client: client}, nil
}

// Close closes the underlying SSH client connection.
func (r *SSHRunner) Close() {
	r.client.Close()
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
		return string(output), fmt.Errorf("failed to run command '%s': %w", cmd, err)
	}
	return string(output), nil
}

// Upload copies a file to the remote host using SCP.
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
		// SCP protocol: C<mode> <size> <filename>\n
		fmt.Fprintf(w, "C%#o %d %s\n", stat.Mode().Perm(), stat.Size(), filepath.Base(destPath))
		io.Copy(w, f)
		fmt.Fprint(w, "\x00") // End of transfer
	}()

	// The -t flag indicates "target" mode for scp.
	cmd := fmt.Sprintf("scp -t %s", filepath.Dir(destPath))
	if output, err := session.CombinedOutput(cmd); err != nil {
		return fmt.Errorf("scp upload failed: %w, output: %s", err, string(output))
	}
	return nil
}

// Download copies a file from the remote host using SCP.
// NOTE: This is a simplified implementation for a single file download. It does not handle directories.
func (r *SSHRunner) Download(srcPath, destPath string) error {
	session, err := r.client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	// The -f flag indicates "source" mode for scp.
	cmd := fmt.Sprintf("scp -f %s", srcPath)

	// Set up pipes
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

	// SCP protocol handshake: send a null byte to start the transfer.
	stdin.Write([]byte{0})

	// Create the destination directory if it doesn't exist
	if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
		return fmt.Errorf("failed to create destination directory '%s': %w", destPath, err)
	}

	// Create the destination file
	f, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("failed to create destination file '%s': %w", destPath, err)
	}
	defer f.Close()

	// Read SCP header from stdout
	headerBuf := make([]byte, 1024)
	n, err := stdout.Read(headerBuf)
	if err != nil {
		return fmt.Errorf("failed to read scp header: %w", err)
	}
	header := string(headerBuf[:n])

	if strings.HasPrefix(header, "C") {
		// This is the file content. Write it.
		// A more robust implementation would parse mode, size, and filename from the header.
		_, err = io.Copy(f, stdout)
		if err != nil {
			return fmt.Errorf("failed to write file content: %w", err)
		}
	} else if strings.HasPrefix(header, "\x01") { // SCP error code
		return fmt.Errorf("scp download error from server: %s", header[1:])
	} else {
		return fmt.Errorf("unexpected scp header: %s", header)
	}

	// Send a final null byte to acknowledge receipt
	stdin.Write([]byte{0})

	if err := session.Wait(); err != nil {
		return fmt.Errorf("scp command wait failed: %w", err)
	}

	return nil
}
