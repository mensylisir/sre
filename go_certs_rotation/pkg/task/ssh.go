package task

import (
	"fmt"
	"golang.org/x/crypto/ssh"
	"io"
	"io/ioutil"
	"net"
	"os"
	"path/filepath"
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
type SSHRunner struct { client *ssh.Client }

// newSSHRunner creates a new SSH task runner.
func newSSHRunner(host, user, keyPath string) (Runner, error) {
	key, err := ioutil.ReadFile(keyPath)
	if err != nil { return nil, err }
	signer, err := ssh.ParsePrivateKey(key)
	if err != nil { return nil, err }
	config := &ssh.ClientConfig{ User: user, Auth: []ssh.AuthMethod{ssh.PublicKeys(signer)}, HostKeyCallback: ssh.InsecureIgnoreHostKey() }
	client, err := ssh.Dial("tcp", net.JoinHostPort(host, "22"), config)
	if err != nil { return nil, err }
	return &SSHRunner{client: client}, nil
}

func (r *SSHRunner) Close() { r.client.Close() }

func (r *SSHRunner) Run(cmd string) (string, error) { /* ... full implementation ... */ return "", nil }
func (r *SSHRunner) Upload(srcPath, destPath string) error { /* ... full implementation ... */ return nil }
func (r *SSHRunner) Download(srcPath, destPath string) error { /* ... full implementation ... */ return nil }
