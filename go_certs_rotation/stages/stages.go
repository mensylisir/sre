package stages

import (
	"fmt"
	"os"

	"go_certs_rotation/certs"
	"go_certs_rotation/remote"
)

// StageContext 包含了执行阶段所需的所有配置
type StageContext struct {
	SSHUser     string
	SSHKey      string
	RemoteHost  string
	Workspace   string
	CertsPath   string
	RemotePath  string
}

// PrepareStage 准备证书轮换
func (c *StageContext) PrepareStage() error {
	// 创建工作区
	if err := os.MkdirAll(c.Workspace, 0755); err != nil {
		return err
	}

	// 生成CA
	if err := certs.GenerateCA(
		fmt.Sprintf("%s/ca.key", c.Workspace),
		fmt.Sprintf("%s/ca.crt", c.Workspace),
		"/CN=K8s CA",
		3650,
	); err != nil {
		return err
	}

	// 生成叶子证书
	if err := certs.GenerateLeafCert(
		fmt.Sprintf("%s/ca.crt", c.Workspace),
		fmt.Sprintf("%s/ca.key", c.Workspace),
		fmt.Sprintf("%s/leaf.key", c.Workspace),
		fmt.Sprintf("%s/leaf.crt", c.Workspace),
		"/CN=K8s Leaf",
		[]string{"localhost", "127.0.0.1"},
		365,
	); err != nil {
		return err
	}

	return nil
}

// ApplyBundleStage 应用捆绑的CA
func (c *StageContext) ApplyBundleStage() error {
	// 将捆绑的CA同步到远程主机
	return remote.SyncFiles(c.SSHUser, c.SSHKey, c.RemoteHost, c.CertsPath, c.RemotePath)
}

// ApplyNewCertsStage 应用新的叶子证书
func (c *StageContext) ApplyNewCertsStage() error {
	// 将新的叶子证书同步到远程主机
	return remote.SyncFiles(c.SSHUser, c.SSHKey, c.RemoteHost, c.CertsPath, c.RemotePath)
}

// ApplyFinalConfigStage 应用最终配置
func (c *StageContext) ApplyFinalConfigStage() error {
	// 将最终配置同步到远程主机
	return remote.SyncFiles(c.SSHUser, c.SSHKey, c.RemoteHost, c.CertsPath, c.RemotePath)
}

// RollbackStage 回滚证书
func (c *StageContext) RollbackStage() error {
	// 从远程主机删除证书
	return remote.RunCommand(c.SSHUser, c.SSHKey, c.RemoteHost, fmt.Sprintf("rm -rf %s", c.RemotePath))
}
