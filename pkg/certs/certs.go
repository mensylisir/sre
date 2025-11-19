package certs
import ("crypto/rand"; "crypto/rsa"; "crypto/x509"; "crypto/x509/pkix"; "encoding/pem"; "fmt"; "io/ioutil"; "math/big"; "net"; "strings"; "time")
type CertSpec struct { Subject pkix.Name; SANs []string; ExpiryDays int; ExtKeyUsage []x509.ExtKeyUsage; IsCA bool }
func GenerateCertificate(spec CertSpec, caCertPEM, caKeyPEM []byte) (certPEM, keyPEM []byte, err error) {
	privKey, err := rsa.GenerateKey(rand.Reader, 2048); if err != nil { return nil, nil, err }
	template := &x509.Certificate{ SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: spec.Subject, NotBefore: time.Now(), NotAfter: time.Now().AddDate(0, 0, spec.ExpiryDays), BasicConstraintsValid: true }
	for _, san := range spec.SANs { if ip := net.ParseIP(san); ip != nil { template.IPAddresses = append(template.IPAddresses, ip) } else { template.DNSNames = append(template.DNSNames, san) } }
	if spec.IsCA { template.IsCA = true; template.KeyUsage = x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign | x509.KeyUsageCRLSign } else { template.KeyUsage = x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment; template.ExtKeyUsage = spec.ExtKeyUsage }
	var parentCert *x509.Certificate; var parentKey *rsa.PrivateKey
	if spec.IsCA { parentCert, parentKey = template, privKey } else {
		caCertBlock, _ := pem.Decode(caCertPEM); parentCert, err = x509.ParseCertificate(caCertBlock.Bytes); if err != nil { return nil, nil, err }
		caKeyBlock, _ := pem.Decode(caKeyPEM); parentKey, err = x509.ParsePKCS1PrivateKey(caKeyBlock.Bytes); if err != nil { return nil, nil, err }
	}
	derBytes, err := x509.CreateCertificate(rand.Reader, template, parentCert, &privKey.PublicKey, parentKey); if err != nil { return nil, nil, err }
	certPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	keyPEM = pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privKey)})
	return certPEM, keyPEM, nil
}
func GenerateSAKeyPair() (pubPEM, privPEM []byte, err error) {
	privKey, err := rsa.GenerateKey(rand.Reader, 2048); if err != nil { return nil, nil, err }
	pubBytes, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey); if err != nil { return nil, nil, err }
	privPEM = pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privKey)})
	pubPEM = pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes})
	return pubPEM, privPEM, nil
}
func ParseSubject(subj string) (pkix.Name, error) {
	name := pkix.Name{}; subj = strings.TrimPrefix(subj, "/"); parts := strings.Split(subj, "/");
	for _, part := range parts {
		if strings.TrimSpace(part) == "" { continue }; kv := strings.SplitN(part, "=", 2)
		if len(kv) != 2 { return name, fmt.Errorf("invalid subject part: %s", part) }
		key, value := strings.TrimSpace(kv[0]), strings.TrimSpace(kv[1])
		switch key { case "CN": name.CommonName = value; case "O": name.Organization = append(name.Organization, value) }
	}
	if name.CommonName == "" { return name, fmt.Errorf("subject must contain CN") }; return name, nil
}
func ExtractSANs(certPath string) ([]string, error) {
    certBytes, err := ioutil.ReadFile(certPath); if err != nil { return nil, err }
    block, _ := pem.Decode(certBytes); if block == nil { return nil, fmt.Errorf("failed to decode PEM") }
    cert, err := x509.ParseCertificate(block.Bytes); if err != nil { return nil, err }
    var sans []string; sans = append(sans, cert.DNSNames...); for _, ip := range cert.IPAddresses { sans = append(sans, ip.String()) }; return sans, nil
}
