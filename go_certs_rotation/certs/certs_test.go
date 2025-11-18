package certs

import (
	"os"
	"testing"
)

func TestGenerateCA(t *testing.T) {
	err := GenerateCA("test_ca.key", "test_ca.crt", "/CN=Test CA", 365)
	if err != nil {
		t.Fatalf("Failed to generate CA: %v", err)
	}

	if _, err := os.Stat("test_ca.key"); os.IsNotExist(err) {
		t.Error("CA key file was not created.")
	}

	if _, err := os.Stat("test_ca.crt"); os.IsNotExist(err) {
		t.Error("CA cert file was not created.")
	}

	// Cleanup
	os.Remove("test_ca.key")
	os.Remove("test_ca.crt")
}

func TestGenerateLeafCert(t *testing.T) {
	// Prerequisite: Generate a CA
	if err := GenerateCA("test_ca.key", "test_ca.crt", "/CN=Test CA", 365); err != nil {
		t.Fatalf("Failed to generate prerequisite CA: %v", err)
	}

	sans := []string{"localhost", "127.0.0.1"}
	err := GenerateLeafCert("test_ca.crt", "test_ca.key", "test_leaf.key", "test_leaf.crt", "/CN=Test Leaf", sans, 365)
	if err != nil {
		t.Fatalf("Failed to generate leaf certificate: %v", err)
	}

	if _, err := os.Stat("test_leaf.key"); os.IsNotExist(err) {
		t.Error("Leaf key file was not created.")
	}

	if _, err := os.Stat("test_leaf.crt"); os.IsNotExist(err) {
		t.Error("Leaf cert file was not created.")
	}

	// Cleanup
	os.Remove("test_ca.key")
	os.Remove("test_ca.crt")
	os.Remove("test_leaf.key")
	os.Remove("test_leaf.crt")
}
