package config

import (
	"os"
	"gopkg.in/yaml.v3"
)

// Config holds all configuration for the certificate rotation tool.
type Config struct {
	WorkspaceDir    string            `yaml:"workspace_dir"`
	HostsFile       string            `yaml:"hosts_file"`
	EtcdNodes       []string          `yaml:"etcd_nodes"`
	MasterNodes     []string          `yaml:"master_nodes"`
	SSH             SSHConfig         `yaml:"ssh"`
	RemotePaths     RemotePathsConfig `yaml:"remote_paths"`
	EtcdClientPort  string            `yaml:"etcd_client_port"`
	NewCertConfig   NewCertConfig     `yaml:"new_cert_config"`
}

// SSHConfig holds SSH connection details.
type SSHConfig struct {
	User string `yaml:"user"`
	Key  string `yaml:"key"`
}

// RemotePathsConfig holds paths on the remote nodes.
type RemotePathsConfig struct {
	K8sConfigDir string `yaml:"k8s_config_dir"`
	EtcdSSLDir   string `yaml:"etcd_ssl_dir"`
	KubeletConf  string `yaml:"kubelet_conf"`
	EtcdEnvFile  string `yaml:"etcd_env_file"`
	EtcdctlPath  string `yaml:"etcdctl_path"`
}

// NewCertConfig holds parameters for generating new certificates.
type NewCertConfig struct {
	CAExpiryDays        int    `yaml:"ca_expiry_days"`
	CertExpiryDays      int    `yaml:"cert_expiry_days"`
	K8sCASubject        string `yaml:"k8s_ca_subject"`
	EtcdCASubject       string `yaml:"etcd_ca_subject"`
	FrontProxyCASubject string `yaml:"front_proxy_ca_subject"`
}

// LoadConfig reads configuration from a YAML file.
func LoadConfig(path string) (*Config, error) {
	config := &Config{}

	file, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	err = yaml.Unmarshal(file, config)
	if err != nil {
		return nil, err
	}

	return config, nil
}
