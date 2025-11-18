package certs

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"os"
	"time"
)

// GenerateCA 生成一个新的CA证书和私钥
func GenerateCA(keyPath, certPath, subject string, expiryDays int) error {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return err
	}

	template := x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: subject},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(0, 0, expiryDays),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		return err
	}

	certOut, err := os.Create(certPath)
	if err != nil {
		return err
	}
	defer certOut.Close()
	pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes})

	keyOut, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	defer keyOut.Close()
	pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	return nil
}

// GenerateLeafCert 生成一个新的叶子证书和私钥
func GenerateLeafCert(caCertPath, caKeyPath, keyPath, certPath, subject string, sans []string, expiryDays int) error {
	caCertFile, err := os.ReadFile(caCertPath)
	if err != nil {
		return err
	}
	caCertBlock, _ := pem.Decode(caCertFile)
	caCert, err := x509.ParseCertificate(caCertBlock.Bytes)
	if err != nil {
		return err
	}

	caKeyFile, err := os.ReadFile(caKeyPath)
	if err != nil {
		return err
	}
	caKeyBlock, _ := pem.Decode(caKeyFile)
	caKey, err := x509.ParsePKCS1PrivateKey(caKeyBlock.Bytes)
	if err != nil {
		return err
	}

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return err
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: subject},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().AddDate(0, 0, expiryDays),
		KeyUsage:     x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
	}

	for _, san := range sans {
		if ip := net.ParseIP(san); ip != nil {
			template.IPAddresses = append(template.IPAddresses, ip)
		} else {
			template.DNSNames = append(template.DNSNames, san)
		}
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, &template, caCert, &priv.PublicKey, caKey)
	if err != nil {
		return err
	}

	certOut, err := os.Create(certPath)
	if err != nil {
		return err
	}
	defer certOut.Close()
	pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes})

	keyOut, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	defer keyOut.Close()
	pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	return nil
}
