package config

import (
	"os"
	"gopkg.in/yaml.v3"
)

// Config defines the structure for the application's configuration.
type Config struct {
	// KubeconfigPath is the path to the Kubernetes configuration file.
	KubeconfigPath string `yaml:"kubeconfigPath"`
	// SSH holds the SSH connection details.
	SSH SSHConfig `yaml:"ssh"`
    // Workspace is a local directory to store backups and generated certs.
    Workspace string `yaml:"workspace"`
}

// SSHConfig defines SSH connection parameters.
type SSHConfig struct {
	// User is the SSH user for connecting to the nodes.
	User string `yaml:"user"`
	// KeyPath is the path to the SSH private key.
	KeyPath string `yaml:"keyPath"`
}

// LoadConfig reads and parses the configuration from a YAML file.
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
