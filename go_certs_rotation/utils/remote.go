package utils

import (
	"bytes"
	"fmt"
	"golang.org/x/crypto/ssh"
	"io/ioutil"
	"os/exec"
)

// RunCommand executes a command on a remote host.
func RunCommand(host, user, keyPath, cmd string) (string, error) {
	key, err := ioutil.ReadFile(keyPath)
	if err != nil {
		return "", fmt.Errorf("failed to read private key: %w", err)
	}

	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		return "", fmt.Errorf("failed to parse private key: %w", err)
	}

	config := &ssh.ClientConfig{
		User: user,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(signer),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
	}

	client, err := ssh.Dial("tcp", host+":22", config)
	if err != nil {
		return "", fmt.Errorf("failed to dial: %w", err)
	}
	defer client.Close()

	session, err := client.NewSession()
	if err != nil {
		return "", fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	var b bytes.Buffer
	session.Stdout = &b
	session.Stderr = &b

	if err := session.Run(cmd); err != nil {
		return b.String(), fmt.Errorf("failed to run command: %w", err)
	}

	return b.String(), nil
}

// SyncToRemote synchronizes files to a remote host using rsync.
func SyncToRemote(host, user, keyPath, src, dest string) error {
    sshCmd := fmt.Sprintf("ssh -i %s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null", keyPath)
	cmd := exec.Command("rsync", "-avz", "-e", sshCmd, src, fmt.Sprintf("%s@%s:%s", user, host, dest))

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("rsync failed: %w\nOutput: %s", err, string(output))
	}
	return nil
}

// SyncFromRemote synchronizes files from a remote host using rsync.
func SyncFromRemote(host, user, keyPath, src, dest string) error {
    sshCmd := fmt.Sprintf("ssh -i %s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null", keyPath)
	cmd := exec.Command("rsync", "-avz", "-e", sshCmd, fmt.Sprintf("%s@%s:%s", user, host, src), dest)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("rsync failed: %w\nOutput: %s", err, string(output))
	}
	return nil
}
