package certs

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"math/big"
	"net"
	"os"
	"strings"
	"time"
)

// LoadCertificate loads a certificate from a PEM file.
func LoadCertificate(path string) (*x509.Certificate, error) {
	certBytes, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read certificate file: %w", err)
	}

	block, _ := pem.Decode(certBytes)
	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM block from %s", path)
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse certificate: %w", err)
	}

	return cert, nil
}

// LoadPrivateKey loads a private key from a PEM file.
func LoadPrivateKey(path string) (*rsa.PrivateKey, error) {
	keyBytes, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read private key file: %w", err)
	}

	block, _ := pem.Decode(keyBytes)
	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM block from %s", path)
	}

	key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse private key: %w", err)
	}

	return key, nil
}

// GenerateCA creates a new self-signed CA certificate.
func GenerateCA(keyPath, certPath string, subject pkix.Name, days int) error {
	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return fmt.Errorf("failed to generate private key: %w", err)
	}

	template := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               subject,
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(0, 0, days),
		IsCA:                  true,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, template, template, &privKey.PublicKey, privKey)
	if err != nil {
		return fmt.Errorf("failed to create certificate: %w", err)
	}

	// Write certificate to file
	certOut, err := os.Create(certPath)
	if err != nil {
		return fmt.Errorf("failed to open cert file for writing: %w", err)
	}
	defer certOut.Close()
	if err := pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes}); err != nil {
		return fmt.Errorf("failed to write certificate: %w", err)
	}

	// Write key to file
	keyOut, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return fmt.Errorf("failed to open key file for writing: %w", err)
	}
	defer keyOut.Close()
	if err := pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privKey)}); err != nil {
		return fmt.Errorf("failed to write key: %w", err)
	}

	return nil
}

// GenerateLeafCert creates a new leaf certificate signed by the given CA.
func GenerateLeafCert(keyPath, certPath string, caCert *x509.Certificate, caKey *rsa.PrivateKey,
	subject pkix.Name, sans []string, days int, eku []x509.ExtKeyUsage) error {

	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return fmt.Errorf("failed to generate private key: %w", err)
	}

	template := &x509.Certificate{
		SerialNumber:   big.NewInt(time.Now().Unix()),
		Subject:        subject,
		NotBefore:      time.Now(),
		NotAfter:       time.Now().AddDate(0, 0, days),
		KeyUsage:       x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:    eku,
		IsCA:           false,
	}

	for _, san := range sans {
		if ip := net.ParseIP(san); ip != nil {
			template.IPAddresses = append(template.IPAddresses, ip)
		} else {
			template.DNSNames = append(template.DNSNames, san)
		}
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, template, caCert, &privKey.PublicKey, caKey)
	if err != nil {
		return fmt.Errorf("failed to create certificate: %w", err)
	}

	// Write certificate to file
	certOut, err := os.Create(certPath)
	if err != nil {
		return fmt.Errorf("failed to open cert file for writing: %w", err)
	}
	defer certOut.Close()
	if err := pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes}); err != nil {
		return fmt.Errorf("failed to write certificate: %w", err)
	}

	// Write key to file
	keyOut, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return fmt.Errorf("failed to open key file for writing: %w", err)
	}
	defer keyOut.Close()
	if err := pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privKey)}); err != nil {
		return fmt.Errorf("failed to write key: %w", err)
	}

	return nil
}

// ParseSubject parses a string like "/CN=kubernetes/O=system:masters" into a pkix.Name.
func ParseSubject(subj string) (pkix.Name, error) {
	name := pkix.Name{}
	parts := strings.Split(subj, "/")
	for _, part := range parts {
		if strings.TrimSpace(part) == "" {
			continue
		}
		kv := strings.SplitN(part, "=", 2)
		if len(kv) != 2 {
			return name, fmt.Errorf("invalid subject part: %s", part)
		}
		key := strings.TrimSpace(kv[0])
		value := strings.TrimSpace(kv[1])

		switch key {
		case "CN":
			name.CommonName = value
		case "O":
			name.Organization = append(name.Organization, value)
		}
	}
	return name, nil
}
