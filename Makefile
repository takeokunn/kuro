.PHONY: all build test clean install lint fmt check test-safe vttest-compliance bench-validate test-elisp run

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
	bash test/shell/run-e2e.sh

# Run safe unit tests only (no PTY, no tmux — safe inside tmux/opencode sessions)
test-safe:
	$(CARGO) test --workspace
	emacs -Q --batch \
	  -L emacs-lisp -L test/unit \
	  --eval "(require 'kuro-config)" \
	  --eval "(require 'kuro-config-test)" \
	  --eval "(ert-run-tests-batch-and-exit \"test-kuro\")"

# VTE compliance check (Rust-only, no PTY required)
vttest-compliance:
	bash test/shell/vttest-compliance.sh

# Benchmark validation (checks >100MB/s parse rate)
bench-validate:
	bash test/shell/bench-validate.sh

# Run Elisp ERT tests (no Rust module required)
test-elisp:
	$(EMACS) -Q --batch \
		-L emacs-lisp \
		-L test/unit \
		-L test/integration \
		--eval "(setq load-prefer-newer t)" \
		--eval "(load (expand-file-name \"test/unit/kuro-test.el\"))" \
		--eval "(mapc (function load) (seq-remove (lambda (f) (string-suffix-p \"/kuro-test.el\" f)) (directory-files (expand-file-name \"test/unit\") t \".el$$\")))" \
		--eval "(mapc (function load) (directory-files (expand-file-name \"test/integration\") t \".el$$\"))" \
		--eval "(ert-run-tests-batch-and-exit)"

# Run all tests
test-all: test test-e2e test-elisp

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

# Run Kuro as a macOS GUI application (Dock icon, Cmd+Tab, keyboard focus)
run: build install
ifeq ($(UNAME_S),Darwin)
	@EMACS_PREFIX=$$(dirname $$(dirname $$(realpath $$(which $(EMACS))))); \
	EMACS_APP="$$EMACS_PREFIX/Applications/Emacs.app"; \
	if [ -d "$$EMACS_APP" ]; then \
		open -n -a "$$EMACS_APP" --args -Q \
			--eval "(add-to-list 'load-path \"$(CURDIR)/emacs-lisp\")" \
			--eval "(setenv \"KURO_MODULE_PATH\" \"$(CURDIR)/$(TARGET_DIR)\")" \
			--eval "(require 'kuro)" \
			--eval "(kuro-create \"/bin/bash\")"; \
	else \
		echo "Error: Emacs.app not found at $$EMACS_APP" >&2; \
		echo "Install Emacs with an .app bundle (e.g. via nix or homebrew)" >&2; \
		exit 1; \
	fi
else
	@exec $(EMACS) -Q \
		--eval "(add-to-list 'load-path \"$(CURDIR)/emacs-lisp\")" \
		--eval "(setenv \"KURO_MODULE_PATH\" \"$(CURDIR)/$(TARGET_DIR)\")" \
		--eval "(require 'kuro)" \
		--eval "(kuro-create \"/bin/bash\")"
endif

# Documentation
doc:
	$(CARGO) doc --workspace --no-deps --open
