package stages

import (
	"bufio"
	"crypto/x509"
	"encoding/base64"
	"fmt"
	"go_certs_rotation/certs"
	"go_certs_rotation/config"
	"go_certs_rotation/utils"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"gopkg.in/yaml.v3"
)

// ... (All other functions remain the same) ...

func updateKubeconfigs(cfg *config.Config, ipToHostname map[string]string, hosts []string) error {
    k8sBundle, err := ioutil.ReadFile(filepath.Join(cfg.WorkspaceDir, "k8s-bundle.crt"))
    if err != nil {
        return err
    }
    k8sBundleBase64 := base64.StdEncoding.EncodeToString(k8sBundle)

    for _, ip := range hosts {
        hostname := ipToHostname[ip]
        bundleDir := filepath.Join(cfg.WorkspaceDir, hostname, "bundle")

        confFiles, err := filepath.Glob(filepath.Join(cfg.WorkspaceDir, hostname, "old", "*.conf"))
        if err != nil {
            continue
        }

        for _, f := range confFiles {
            dest := filepath.Join(bundleDir, filepath.Base(f))

            content, err := ioutil.ReadFile(f)
            if err != nil {
                return err
            }

            var kubeconfig map[string]interface{}
            if err := yaml.Unmarshal(content, &kubeconfig); err != nil {
                // Not a valid YAML, just copy it
                ioutil.WriteFile(dest, content, 0644)
                continue
            }

            // Update CA data in clusters section
            if clusters, ok := kubeconfig["clusters"].([]interface{}); ok {
                for _, c := range clusters {
                    if cluster, ok := c.(map[string]interface{}); ok {
                        if clusterDetails, ok := cluster["cluster"].(map[string]interface{}); ok {
                            clusterDetails["certificate-authority-data"] = k8sBundleBase64
                        }
                    }
                }
            }

            newContent, err := yaml.Marshal(&kubeconfig)
            if err != nil {
                return err
            }

            ioutil.WriteFile(dest, newContent, 0644)
        }
    }
    return nil
}

// ... (Rest of the helper functions from the previous turn)
// ... (loadHosts, getHostnames)

func backupConfigs(hosts []string, ipToHostname map[string]string, cfg *config.Config) error {
    for _, ip := range hosts {
        hostname := ipToHostname[ip]
        utils.InfoLogger.Printf("Backing up config for node %s (%s)", hostname, ip)

        nodeDir := filepath.Join(cfg.WorkspaceDir, hostname)
        oldDir := filepath.Join(nodeDir, "old")
        newDir := filepath.Join(nodeDir, "new")
        bundleDir := filepath.Join(nodeDir, "bundle")
        os.MkdirAll(oldDir, 0755)
        os.MkdirAll(newDir, 0755)
        os.MkdirAll(bundleDir, 0755)

        if err := utils.SyncFromRemote(ip, cfg.SSH.User, cfg.SSH.Key, cfg.RemotePaths.KubeletConf, filepath.Join(oldDir, "kubelet.conf")); err != nil { return err }

        if contains(cfg.MasterNodes, ip) {
            if err := utils.SyncFromRemote(ip, cfg.SSH.User, cfg.SSH.Key, cfg.RemotePaths.K8sConfigDir+"/", filepath.Join(oldDir, "kubernetes")); err != nil { return err }
            confFiles, _ := filepath.Glob(filepath.Join(oldDir, "kubernetes", "*.conf"))
            for _, f := range confFiles {
                os.Link(f, filepath.Join(oldDir, filepath.Base(f)))
            }
        }

        if contains(cfg.EtcdNodes, ip) {
             if err := utils.SyncFromRemote(ip, cfg.SSH.User, cfg.SSH.Key, cfg.RemotePaths.EtcdSSLDir+"/", filepath.Join(oldDir, "etcd-ssl")); err != nil { return err }
        }
    }
    return nil
}

func generateCAs(cfg *config.Config) (k8sCAPaths, etcdCAPaths, frontProxyCAPaths map[string]string, err error) {
    newCAsDir := filepath.Join(cfg.WorkspaceDir, "new-cas")

    k8sCASubject, _ := certs.ParseSubject(cfg.NewCertConfig.K8sCASubject)
    k8sCAPaths = map[string]string{
        "key":  filepath.Join(newCAsDir, "kubernetes", "ca.key"),
        "cert": filepath.Join(newCAsDir, "kubernetes", "ca.crt"),
    }
    os.MkdirAll(filepath.Dir(k8sCAPaths["key"]), 0755)
    if err = certs.GenerateCA(k8sCAPaths["key"], k8sCAPaths["cert"], k8sCASubject, cfg.NewCertConfig.CAExpiryDays); err != nil { return }

    etcdCASubject, _ := certs.ParseSubject(cfg.NewCertConfig.EtcdCASubject)
    etcdCAPaths = map[string]string{
        "key":  filepath.Join(newCAsDir, "etcd", "ca-key.pem"),
        "cert": filepath.Join(newCAsDir, "etcd", "ca.pem"),
    }
    os.MkdirAll(filepath.Dir(etcdCAPaths["key"]), 0755)
    if err = certs.GenerateCA(etcdCAPaths["key"], etcdCAPaths["cert"], etcdCASubject, cfg.NewCertConfig.CAExpiryDays); err != nil { return }

    frontProxyCASubject, _ := certs.ParseSubject(cfg.NewCertConfig.FrontProxyCASubject)
    frontProxyCAPaths = map[string]string{
        "key":  filepath.Join(newCAsDir, "front-proxy", "ca.key"),
        "cert": filepath.Join(newCAsDir, "front-proxy", "ca.crt"),
    }
    os.MkdirAll(filepath.Dir(frontProxyCAPaths["key"]), 0755)
    if err = certs.GenerateCA(frontProxyCAPaths["key"], frontProxyCAPaths["cert"], frontProxyCASubject, cfg.NewCertConfig.CAExpiryDays); err != nil { return }

    return
}

type allSANs struct {
	k8sApiserver   []string
	etcdAdmin      []string
	etcdNode       []string
	etcdMember     []string
}

func extractSANs(cfg *config.Config, ipToHostname map[string]string) (*allSANs, error) {
    firstMasterHostname := ipToHostname[cfg.MasterNodes[0]]
    firstEtcdHostname := ipToHostname[cfg.EtcdNodes[0]]

    k8sApiserver, err := utils.ExtractSANsFromCert(filepath.Join(cfg.WorkspaceDir, firstMasterHostname, "old", "kubernetes", "pki", "apiserver.crt"))
    if err != nil { return nil, err }
    etcdAdmin, err := utils.ExtractSANsFromCert(filepath.Join(cfg.WorkspaceDir, firstEtcdHostname, "old", "etcd-ssl", fmt.Sprintf("admin-%s.pem", firstEtcdHostname)))
    if err != nil { return nil, err }
    etcdNode, err := utils.ExtractSANsFromCert(filepath.Join(cfg.WorkspaceDir, firstEtcdHostname, "old", "etcd-ssl", fmt.Sprintf("node-%s.pem", firstEtcdHostname)))
    if err != nil { return nil, err }
    etcdMember, err := utils.ExtractSANsFromCert(filepath.Join(cfg.WorkspaceDir, firstEtcdHostname, "old", "etcd-ssl", fmt.Sprintf("member-%s.pem", firstEtcdHostname)))
    if err != nil { return nil, err }

    return &allSANs{k8sApiserver, etcdAdmin, etcdNode, etcdMember}, nil
}

func generateAllLeafCerts(cfg *config.Config, ipToHostname map[string]string, hosts []string, k8sCAPaths, etcdCAPaths, frontProxyCAPaths map[string]string, sans *allSANs) error {
    k8sCA, _ := certs.LoadCertificate(k8sCAPaths["cert"])
    k8sCAKey, _ := certs.LoadPrivateKey(k8sCAPaths["key"])
    etcdCA, _ := certs.LoadCertificate(etcdCAPaths["cert"])
    etcdCAKey, _ := certs.LoadPrivateKey(etcdCAPaths["key"])
    frontProxyCA, _ := certs.LoadCertificate(frontProxyCAPaths["cert"])
    frontProxyCAKey, _ := certs.LoadPrivateKey(frontProxyCAPaths["key"])

    for _, ip := range hosts {
        hostname := ipToHostname[ip]
        newDir := filepath.Join(cfg.WorkspaceDir, hostname, "new")

        if contains(cfg.MasterNodes, ip) {
            pkiDir := filepath.Join(newDir, "kubernetes", "pki")
            os.MkdirAll(pkiDir, 0755)

            apiserverSubj, _ := certs.ParseSubject("/CN=kube-apiserver")
            certs.GenerateLeafCert(filepath.Join(pkiDir, "apiserver.key"), filepath.Join(pkiDir, "apiserver.crt"), k8sCA, k8sCAKey, apiserverSubj, sans.k8sApiserver, cfg.NewCertConfig.CertExpiryDays, []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth})

            kubeletClientSubj, _ := certs.ParseSubject("/CN=kube-apiserver-kubelet-client/O=system:masters")
            certs.GenerateLeafCert(filepath.Join(pkiDir, "apiserver-kubelet-client.key"), filepath.Join(pkiDir, "apiserver-kubelet-client.crt"), k8sCA, k8sCAKey, kubeletClientSubj, nil, cfg.NewCertConfig.CertExpiryDays, []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth})

            frontProxyClientSubj, _ := certs.ParseSubject("/CN=front-proxy-client")
            certs.GenerateLeafCert(filepath.Join(pkiDir, "front-proxy-client.key"), filepath.Join(pkiDir, "front-proxy-client.crt"), frontProxyCA, frontProxyCAKey, frontProxyClientSubj, nil, cfg.NewCertConfig.CertExpiryDays, []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth})
        }

        if contains(cfg.EtcdNodes, ip) {
            sslDir := filepath.Join(newDir, "etcd-ssl")
            os.MkdirAll(sslDir, 0755)

            adminSubj, _ := certs.ParseSubject(fmt.Sprintf("/CN=etcd-admin-%s", hostname))
            certs.GenerateLeafCert(filepath.Join(sslDir, fmt.Sprintf("admin-%s-key.pem", hostname)), filepath.Join(sslDir, fmt.Sprintf("admin-%s.pem", hostname)), etcdCA, etcdCAKey, adminSubj, sans.etcdAdmin, cfg.NewCertConfig.CertExpiryDays, []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth})

            nodeSubj, _ := certs.ParseSubject(fmt.Sprintf("/CN=etcd-node-%s", hostname))
            certs.GenerateLeafCert(filepath.Join(sslDir, fmt.Sprintf("node-%s-key.pem", hostname)), filepath.Join(sslDir, fmt.Sprintf("node-%s.pem", hostname)), etcdCA, etcdCAKey, nodeSubj, sans.etcdNode, cfg.NewCertConfig.CertExpiryDays, []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth})

            memberSubj, _ := certs.ParseSubject(fmt.Sprintf("/CN=etcd-member-%s", hostname))
            certs.GenerateLeafCert(filepath.Join(sslDir, fmt.Sprintf("member-%s-key.pem", hostname)), filepath.Join(sslDir, fmt.Sprintf("member-%s.pem", hostname)), etcdCA, etcdCAKey, memberSubj, sans.etcdMember, cfg.NewCertConfig.CertExpiryDays, []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth})
        }
    }
    return nil
}

func createBundledCAs(cfg *config.Config, ipToHostname map[string]string, k8sCAPaths, etcdCAPaths map[string]string) error {
    firstMasterHostname := ipToHostname[cfg.MasterNodes[0]]
    oldK8sCACert, _ := ioutil.ReadFile(filepath.Join(cfg.WorkspaceDir, firstMasterHostname, "old", "kubernetes", "pki", "ca.crt"))
    newK8sCACert, _ := ioutil.ReadFile(k8sCAPaths["cert"])
    k8sBundle := append(oldK8sCACert, newK8sCACert...)
    ioutil.WriteFile(filepath.Join(cfg.WorkspaceDir, "k8s-bundle.crt"), k8sBundle, 0644)

    firstEtcdHostname := ipToHostname[cfg.EtcdNodes[0]]
    oldEtcdCACert, _ := ioutil.ReadFile(filepath.Join(cfg.WorkspaceDir, firstEtcdHostname, "old", "etcd-ssl", "ca.pem"))
    newEtcdCACert, _ := ioutil.ReadFile(etcdCAPaths["cert"])
    etcdBundle := append(oldEtcdCACert, newEtcdCACert...)
    ioutil.WriteFile(filepath.Join(cfg.WorkspaceDir, "etcd-bundle.pem"), etcdBundle, 0644)

    return nil
}
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

// ... (loadHosts, getHostnames must be defined as in the previous turn)
func loadHosts(path string) ([]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var hosts []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" && !strings.HasPrefix(line, "#") {
			hosts = append(hosts, line)
		}
	}
	return hosts, nil
}

func getHostnames(hosts []string, cfg *config.Config) (map[string]string, error) {
	ipToHostname := make(map[string]string)
	for _, ip := range hosts {
		hostname, err := utils.RunCommand(ip, cfg.SSH.User, cfg.SSH.Key, "hostname -s")
		if err != nil {
			return nil, err
		}
		ipToHostname[ip] = strings.TrimSpace(hostname)
	}
	return ipToHostname, nil
}
