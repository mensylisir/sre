package utils

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"strings"
)

// ExtractSANsFromCert extracts the Subject Alternative Names from a certificate.
func ExtractSANsFromCert(certPath string) ([]string, error) {
	certBytes, err := ioutil.ReadFile(certPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read certificate file: %w", err)
	}

	block, _ := pem.Decode(certBytes)
	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM block from certificate")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse certificate: %w", err)
	}

	var sans []string
	sans = append(sans, cert.DNSNames...)
	for _, ip := range cert.IPAddresses {
		sans = append(sans, ip.String())
	}

	return sans, nil
}
