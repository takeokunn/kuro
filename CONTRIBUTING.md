# Contributing to Kuro

Thank you for your interest in contributing!

## Development Setup

### Prerequisites

1. **Rust** (version 1.75.0 or later)
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Emacs** (version 29.1 or later with module support)
   - **macOS**: `brew install emacs`
   - **Ubuntu/Debian**: `sudo apt install emacs`
   - **Arch Linux**: `sudo pacman -S emacs`
   - **From source**: Ensure you build with `--with-modules` flag

3. **Build dependencies**
   - Ubuntu/Debian: `sudo apt install build-essential`
   - macOS: `xcode-select --install`
   - Fedora: `sudo dnf install gcc make`

### Verification

Verify your installation:
```bash
# Check Rust version
rustc --version

# Check Emacs has module support
emacs --batch --eval "(if (fboundp 'module-load) (message \"Module support: YES\") (error \"Module support: NO\"))"
```

### Build from Source

```bash
# Clone repository
git clone https://github.com/takeokunn/kuro.git
cd kuro

# Development build (faster compilation, less optimized)
cargo build --workspace

# Release build (optimized, for production)
cargo build --release --workspace

# The compiled dynamic module will be at:
# - Linux: target/release/libkuro_core.so
# - macOS: target/release/libkuro_core.dylib
# - Windows: target/release/kuro_core.dll

# Run tests
cargo test --workspace

# Format code
cargo fmt --all

# Lint
cargo clippy --workspace -- -D warnings
```

### Module Loading

There are two ways to load the Kuro module in Emacs:

**Option 1: Using module-load (recommended for development)**
```elisp
;; Add to your Emacs config
(add-to-list 'load-path "~/path/to/kuro/emacs-lisp")

;; Load the Elisp files
(require 'kuro)

;; The Rust module will be loaded automatically when needed
```

**Option 2: Manual module loading**
```elisp
;; Load the Rust module explicitly
(module-load "~/path/to/kuro/target/release/libkuro_core.dylib")  ; macOS
;; or
(module-load "~/path/to/kuro/target/release/libkuro_core.so")  ; Linux

;; Then load Elisp
(require 'kuro)
```

### Hot-Reload Workflow for Development

For rapid development, use this workflow:

1. **Initial setup:**
   ```bash
   # Build once
   cargo build --release
   ```

2. **For Rust changes:**
   ```bash
   # Rebuild
   cargo build --release

   # In Emacs, reload the module
   (unload-feature 'kuro)
   (require 'kuro)
   ```

3. **For Elisp changes:**
   ```elisp
   ; In Emacs, just eval the buffer
   M-x eval-buffer
   ; or
   M-x load-file RET ~/path/to/kuro/emacs-lisp/kuro.el
   ```

4. **Quick test loop:**
   ```bash
   # Terminal 1: Watch for changes and rebuild
   cargo watch -x 'build --release'

   # Emacs: Reload module when build completes
   M-x kuro-reload
   ```

### Development Workflow

1. Create feature branch: `git checkout -b feature/your-feature`
2. Write tests alongside code
3. Ensure >80% code coverage
4. Run `make ci` to verify all checks pass
5. Submit PR with descriptive title and description

### Code Style

- Rust: Follow `rustfmt` formatting
- Elisp: Follow Elisp style guide (`M-x elisp-lint-mode`)
- Commit messages: Conventional Commits format

### Testing

#### Elisp Tests (ERT)

Kuro uses Emacs Lisp's built-in testing framework (ERT) for testing the Elisp components.

```bash
# Run all Elisp tests (unit + E2E)
make test-e2e

# Run specific test file
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro-renderer-unit-test)" \
  --eval "(ert-run-tests-batch-and-exit \"test-kuro\")"

# Run all tests including Rust
make test-all

# Run only Rust tests
make test
```

**Test Files:**
- `test/kuro-renderer-unit-test.el` - Unit tests for kuro-renderer.el (pure Elisp, no Rust module needed)
- `test/kuro-e2e-test.el` - End-to-end tests requiring Rust module and PTY
- `test/kuro-config-test.el` - Unit tests for kuro-config.el

**Running Specific Test Categories:**

```bash
# Run only E2E tests (requires built module)
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro)" \
  --eval "(require 'kuro-e2e-test)" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-e2e\")"

# Run only config unit tests
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro-config)" \
  --eval "(require 'kuro-config-test)" \
  --eval "(ert-run-tests-batch-and-exit \"test-kuro\")"

# Run only unit tests from kuro-e2e-test.el
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro)" \
  --eval "(require 'kuro-e2e-test)" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-unit\")"
```

For more detailed test documentation, see [test/README.md](test/README.md).

#### Rust Tests

```bash
# Unit tests
make test

# Integration tests
make test-integration

# Benchmarks
make test-bench

# Coverage report
make coverage
```

### Debugging

See [docs/development/debugging.md](docs/development/debugging.md)

### Troubleshooting

#### Module Load Failures

**Error: "Cannot open shared object file"**
- Check module file exists: `ls -la target/release/libkuro_core.*`
- Verify Emacs was built with module support
- Check file permissions: `chmod +x target/release/libkuro_core.so`

**Error: "Function not defined"**
- Verify module is loaded: `(featurep 'kuro-module)` should return `t`
- List exported functions: `M-x apropos RET kuro-`

**Error: "Version mismatch"**
- Check Emacs version: `emacs --version`
- Minimum required: Emacs 29.1
- Upgrade Emacs if needed

#### PTY Spawn Issues

**Error: "Failed to spawn PTY"**
- Verify shell command exists: `which bash`
- Check permissions: User must have permission to create PTY
- On WSL2, ensure WSL is properly configured

**Error: "PTY operation failed: Broken pipe"**
- Check if shell process has exited
- Verify PTY is still open: `ls /proc/self/fd` (Linux)
- Restart terminal: `(kuro-kill)` then `(kuro-create "bash")`

#### Emacs Version Compatibility

**Issue: Module loads but functions crash**
- Verify Emacs 29.1+ is installed
- Check for module support: `(fboundp 'module-load)`
- Rebuild module after Emacs upgrade

**Issue: Performance issues on older Emacs**
- Upgrade to latest stable Emacs
- Emacs 31+ has improved module performance
- Check `kuro-frame-rate` setting

#### Common Error Patterns

**Pattern: Module works once, then fails**
- Cause: Global state not reset properly
- Solution: `(unload-feature 'kuro)` before reloading

**Pattern: Intermittent crashes on resize**
- Cause: Race condition in PTY
- Solution: Increase debounce timeout in kuro-resize

**Pattern: Garbage characters in buffer**
- Cause: UTF-8 decode error or binary data
- Solution: Check terminal settings, ensure UTF-8 locale

## Project Structure

```
kuro/
├── rust-core/          # Rust library
│   ├── src/
│   │   ├── types/      # Color, Cell types
│   │   ├── grid/       # Line, Screen
│   │   ├── parser/     # VTE parsing
│   │   ├── pty/        # PTY management
│   │   └── ffi/        # Emacs FFI
│   ├── tests/          # Integration tests
│   └── benches/        # Benchmarks
├── emacs-lisp/         # Emacs Lisp UI
│   ├── kuro.el         # Main entry point
│   ├── kuro-ffi.el     # FFI wrappers
│   └── kuro-renderer.el # Render loop
├── docs/               # Documentation
└── test/               # Elisp tests
```

## Architecture Decisions

See [docs/explanation/design-decisions.md](docs/explanation/design-decisions.md)

## Getting Help

- GitHub Issues: Bug reports and feature requests
- Discussions: General questions and ideas
- Docs: [docs/](docs/) directory

## Code Review Process

1. All PRs require CI to pass
2. At least one maintainer approval
3. Code coverage must not decrease
4. All tests must pass
