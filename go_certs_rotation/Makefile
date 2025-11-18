# Simple Makefile for the go-certs-rotation project

# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GOCLEAN=$(GOCMD) clean
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get

# Binary name
BINARY_NAME=go-certs-rotation

# Default target
all: build

# Build the binary for the current platform
build:
	@echo "Building $(BINARY_NAME)..."
	$(GOBUILD) -o $(BINARY_NAME) .

# Clean the binary
clean:
	@echo "Cleaning..."
	$(GOCLEAN)
	rm -f $(BINARY_NAME)

# Run tests
test:
	@echo "Running tests..."
	$(GOTEST) -v ./...

# Cross-compile for Linux (amd64) - useful for building on macOS/Windows for a Linux target
build-linux:
	@echo "Building $(BINARY_NAME) for Linux (amd64)..."
	GOOS=linux GOARCH=amd64 $(GOBUILD) -o $(BINARY_NAME)-linux-amd64 .

.PHONY: all build clean test build-linux
