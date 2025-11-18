package certs

import (
	"crypto/x509/pkix"
)

// GenerateCA creates a new CA.
func GenerateCA(subject pkix.Name) ([]byte, []byte, error) {
	// TODO: Implement CA generation.
	return nil, nil, nil
}

// GenerateLeaf creates a new leaf certificate.
func GenerateLeaf(subject pkix.Name, sans []string, caCert, caKey []byte) ([]byte, []byte, error) {
	// TODO: Implement leaf certificate generation.
	return nil, nil, nil
}
