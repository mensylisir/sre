package remote

import (
	"fmt"
	"os/exec"
)

// RunCommand 在远程主机上运行命令
func RunCommand(user, keyPath, host, command string) error {
	cmd := exec.Command("ssh", "-i", keyPath, fmt.Sprintf("%s@%s", user, host), command)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to run command on %s: %v\n%s", host, err, output)
	}
	return nil
}

// SyncFiles 将文件同步到远程主机
func SyncFiles(user, keyPath, host, src, dest string) error {
	cmd := exec.Command("rsync", "-avz", "-e", fmt.Sprintf("ssh -i %s", keyPath), src, fmt.Sprintf("%s@%s:%s", user, host, dest))
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to sync files to %s: %v\n%s", host, err, output)
	}
	return nil
}

// FetchFiles 从远程主机获取文件
func FetchFiles(user, keyPath, host, src, dest string) error {
	cmd := exec.Command("rsync", "-avz", "-e", fmt.Sprintf("ssh -i %s", keyPath), fmt.Sprintf("%s@%s:%s", user, host, src), dest)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to fetch files from %s: %v\n%s", host, err, output)
	}
	return nil
}
