package config

import (
	"os"
	"gopkg.in/yaml.v3"
)

type Config struct {
	KubeconfigPath string      `yaml:"kubeconfigPath"`
	SSH            SSHConfig   `yaml:"ssh"`
}

type SSHConfig struct {
	User string `yaml:"user"`
	Key  string `yaml:"keyPath"`
}

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
