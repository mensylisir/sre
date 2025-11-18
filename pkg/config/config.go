package config
import ("os"; "gopkg.in/yaml.v3")
type Config struct { KubeconfigPath string `yaml:"kubeconfigPath"`; SSH SSHConfig `yaml:"ssh"`; Workspace string `yaml:"workspace"` }
type SSHConfig struct { User string `yaml:"user"`; KeyPath string `yaml:"keyPath"` }
func LoadConfig(path string) (*Config, error) {
	cfg := &Config{}; file, err := os.ReadFile(path); if err != nil { return nil, err }
	return cfg, yaml.Unmarshal(file, cfg)
}
