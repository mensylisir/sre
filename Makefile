BINARY_NAME=go-certs-rotation
all: build
build:
	go build -o $(BINARY_NAME) .
clean:
	rm -f $(BINARY_NAME)
