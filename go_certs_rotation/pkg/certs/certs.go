package certs

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"strings"
	"time"
)

// CertSpec defines the specification for generating a certificate.
type CertSpec struct {
	Subject      pkix.Name
	SANs         []string
	ExpiryDays   int
	ExtKeyUsage  []x509.ExtKeyUsage
	IsCA         bool
	IsServerCert bool
	IsClientCert bool
}

// GenerateCertificate generates a new certificate and private key based on the provided spec.
// If caCertPEM and caKeyPEM are nil, it generates a self-signed CA. Otherwise, it generates a leaf certificate.
func GenerateCertificate(spec CertSpec, caCertPEM, caKeyPEM []byte) (certPEM, keyPEM []byte, err error) {
	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to generate private key: %w", err)
	}

	template := &x509.Certificate{
		SerialNumber:          big.NewInt(time.Now().UnixNano()),
		Subject:               spec.Subject,
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(0, 0, spec.ExpiryDays),
		BasicConstraintsValid: true,
	}

	// Set SANs
	for _, san := range spec.SANs {
		if ip := net.ParseIP(san); ip != nil {
			template.IPAddresses = append(template.IPAddresses, ip)
		} else {
			template.DNSNames = append(template.DNSNames, san)
		}
	}

	// Set Key Usage
	if spec.IsCA {
		template.IsCA = true
		template.KeyUsage = x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign | x509.KeyUsageCRLSign
	} else {
		template.KeyUsage = x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment
		template.ExtKeyUsage = spec.ExtKeyUsage
	}

	var parentCert *x509.Certificate
	var parentKey *rsa.PrivateKey

	if spec.IsCA {
		// Self-signed
		parentCert = template
		parentKey = privKey
	} else {
		// Signed by a CA
		caCertBlock, _ := pem.Decode(caCertPEM)
		if caCertBlock == nil {
			return nil, nil, fmt.Errorf("failed to decode CA cert PEM")
		}
		parentCert, err = x509.ParseCertificate(caCertBlock.Bytes)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to parse CA cert: %w", err)
		}

		caKeyBlock, _ := pem.Decode(caKeyPEM)
		if caKeyBlock == nil {
			return nil, nil, fmt.Errorf("failed to decode CA key PEM")
		}
		parentKey, err = x509.ParsePKCS1PrivateKey(caKeyBlock.Bytes)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to parse CA key: %w", err)
		}
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, template, parentCert, &privKey.PublicKey, parentKey)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create certificate: %w", err)
	}

	certPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	keyPEM = pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privKey)})

	return certPEM, keyPEM, nil
}

// GenerateSAKeyPair generates a new RSA key pair for service account signing.
func GenerateSAKeyPair() (pubPEM, privPEM []byte, err error) {
	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to generate SA private key: %w", err)
	}

	pubBytes, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to marshal SA public key: %w", err)
	}

	privPEM = pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privKey)})
	pubPEM = pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes})

	return pubPEM, privPEM, nil
}


// ParseSubject parses a string like "/CN=kube-apiserver/O=system:masters" into a pkix.Name.
func ParseSubject(subj string) (pkix.Name, error) {
	name := pkix.Name{}
	// Remove leading slash if present
	subj = strings.TrimPrefix(subj, "/")

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
		// Add other fields like L, ST, C if needed
		}
	}
	if name.CommonName == "" {
		return name, fmt.Errorf("subject must contain a Common Name (CN)")
	}
	return name, nil
}
