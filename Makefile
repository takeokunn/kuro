.PHONY: all build test clean install lint fmt check

# Variables
CARGO = cargo
EMACS = emacs
RUST_CORE = rust-core
TARGET_DIR = target/release

# Default target
all: build

# Build the Rust dynamic module
build:
	$(CARGO) build --release

# Build for development
dev:
	$(CARGO) build

# Run tests
test:
	$(CARGO) test --workspace
	$(CARGO) test --workspace --release

# Run E2E tests (requires built module)
test-e2e: build
	bash test/run-e2e.sh

# Run all tests
test-all: test test-e2e

# Run Clippy
lint:
	$(CARGO) clippy --workspace -- -D warnings

# Format code
fmt:
	$(CARGO) fmt --all

# Check code formatting
check:
	$(CARGO) fmt --all -- --check

# Clean build artifacts
clean:
	$(CARGO) clean
	rm -f emacs-lisp/*.elc

# Install the module to Emacs load path
install: build
	@echo "Installing Kuro module..."
	@echo "Add this to your Emacs config:"
	@echo "(add-to-list 'load-path \"$(PWD)/emacs-lisp\")"
	@echo "(require 'kuro)"
	@echo ""
	@echo "Module location: $(TARGET_DIR)/libkuro_core.so"

# Run development checks
check-all: fmt lint test

# Benchmark (requires nightly Rust)
bench:
	$(CARGO) bench

# Documentation
doc:
	$(CARGO) doc --workspace --no-deps --open
