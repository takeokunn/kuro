.PHONY: all build test clean install lint fmt check test-safe vttest-compliance bench-validate

# Variables
CARGO = cargo
EMACS = emacs
RUST_CORE = rust-core
TARGET_DIR = target/release

# Detect platform-specific library extension
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    LIB_EXT := dylib
else
    LIB_EXT := so
endif
LIB_NAME := libkuro_core.$(LIB_EXT)
INSTALL_DIR := $(HOME)/.local/share/kuro

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

# Run safe unit tests only (no PTY, no tmux — safe inside tmux/opencode sessions)
test-safe:
	$(CARGO) test --workspace
	emacs -Q --batch \
	  -L emacs-lisp -L test \
	  --eval "(require 'kuro-config)" \
	  --eval "(require 'kuro-config-test)" \
	  --eval "(ert-run-tests-batch-and-exit \"test-kuro\")"

# VTE compliance check (Rust-only, no PTY required)
vttest-compliance:
	bash test/vttest-compliance.sh

# Benchmark validation (checks >100MB/s parse rate)
bench-validate:
	bash test/bench-validate.sh

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

# Install the compiled binary to XDG install directory
install:
	$(CARGO) build --release
	mkdir -p $(INSTALL_DIR)
	cp target/release/$(LIB_NAME) $(INSTALL_DIR)/$(LIB_NAME)
	@echo "Kuro: installed $(LIB_NAME) to $(INSTALL_DIR)"

# Run development checks
check-all: fmt lint test

# Benchmark (requires nightly Rust)
bench:
	$(CARGO) bench

# Documentation
doc:
	$(CARGO) doc --workspace --no-deps --open
