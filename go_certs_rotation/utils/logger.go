package utils

import (
	"log"
	"os"
)

var (
	// InfoLogger logs informational messages.
	InfoLogger = log.New(os.Stdout, "[INFO] ", log.Ldate|log.Ltime)
	// ErrorLogger logs error messages.
	ErrorLogger = log.New(os.Stderr, "[ERROR] ", log.Ldate|log.Ltime)
)
