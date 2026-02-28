# Development Setup Guide

This guide will help you set up a development environment for Kuro on your local machine.

## Prerequisites

### Required

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

## Building Kuro

### 1. Clone the Repository

```bash
git clone https://github.com/takeokunn/kuro.git
cd kuro
```

### 2. Build the Rust Core

```bash
# Development build (faster compilation)
make dev

# Release build (optimized)
make build
```

The compiled dynamic module will be at:
- Linux: `target/release/libkuro_core.so`
- macOS: `target/release/libkuro_core.dylib`
- Windows: `target/release/kuro_core.dll`

### 3. Load in Emacs

Add to your Emacs config (e.g., `~/.emacs.d/init.el`):

```elisp
(add-to-list 'load-path "~/path/to/kuro/emacs-lisp")
(require 'kuro)
```

Or evaluate temporarily:
```elisp
(add-to-list 'load-path "/Users/take/ghq/github.com/takeokunn/kuro/emacs-lisp")
(require 'kuro)
```

### 4. Verify Installation

Create a test terminal:
```elisp
;; In Emacs *scratch* buffer
(kuro-create "bash")

;; You should see a new buffer named *kuro*
;; Try typing: echo "Hello, Kuro!"
```

## Hot-Reload Workflow for Development

For rapid development, use this workflow:

### Initial Setup

```bash
# Build once
cargo build --release
```

### For Rust Changes

```bash
# Rebuild the Rust module
cargo build --release

# In Emacs, reload the module
(unload-feature 'kuro)
(require 'kuro)
```

### For Elisp Changes

```elisp
;; In Emacs, just eval the buffer
M-x eval-buffer

;; or reload specific file
M-x load-file RET ~/path/to/kuro/emacs-lisp/kuro.el
```

### Automated Hot-Reload

Use `cargo-watch` for automatic rebuilding:

```bash
# Install cargo-watch
cargo install cargo-watch

# Watch for changes and rebuild automatically
cargo watch -x 'build --release'
```

Then in Emacs, you can create a reload function:

```elisp
(defun kuro-reload ()
  "Reload Kuro module and buffers."
  (interactive)
  (unload-feature 'kuro)
  (require 'kuro)
  (message "Kuro module reloaded"))
```

Bind it to a convenient key:
```elisp
(define-key kuro-mode-map (kbd "C-c C-r") 'kuro-reload)
```

## Development Workflow

### Running Tests

```bash
# Run all tests
make test

# Run tests for specific crate
cargo test -p kuro-core

# Run tests with output
cargo test -- --nocapture

# Run specific test
cargo test test_color_conversion
```

### Code Formatting

```bash
# Format all code
make fmt

# Check formatting without modifying
make check
```

### Linting

```bash
# Run Clippy
make lint
```

### Building Documentation

```bash
# Build and open documentation
make doc
```

## Hot Reload Development

For rapid development during Elisp changes:

1. **Build Rust module once**:
   ```bash
   make build
   ```

2. **Load in Emacs**:
   ```elisp
   (require 'kuro)
   ```

3. **For Elisp changes**: Simply use `M-x eval-buffer` or `M-x load-file`

4. **For Rust changes**:
   - Rebuild: `make build`
   - Restart Emacs or reload module:
     ```elisp
     (unload-feature 'kuro)
     (require 'kuro)
     ```

## Troubleshooting

### Emacs module loading fails

**Error**: `Cannot open shared object file`

**Solution**:
1. Check the module file exists:
   ```bash
   ls -la target/release/libkuro_core.*
   ```
2. Verify Emacs was built with module support
3. Check the path in `kuro-module.el` points to the correct location

### Compilation errors

**Error**: `error: linking with cc failed`

**Solution**:
- Install build dependencies:
  - Ubuntu: `sudo apt install build-essential`
  - macOS: `xcode-select --install`
  - Fedora: `sudo dnf install gcc make`

### Tests fail randomly

**Error**: Flaky test behavior

**Solution**:
- Run tests with `--release` flag for consistency
- Increase test timeout: `cargo test -- --test-threads=1`
- Check for race conditions in concurrent code

### FFI panics crash Emacs

**Error**: Rust panic causes Emacs to crash

**Solution**:
- All FFI functions should use `std::panic::catch_unwind`
- See `ffi/bridge.rs` for proper error handling pattern
- Run with `RUST_BACKTRACE=1` for debugging

## IDE Setup

### VS Code

Install extensions:
- `rust-analyzer`
- `Even Better TOML`

### Emacs with eglot

```elisp
(add-hook 'rust-mode-hook
          (lambda ()
            (eglot-ensure)))
```

### Vim/Neovim with rust-analyzer

See [rust-analyzer documentation](https://rust-analyzer.github.io/manual.html#vim-neovim)

## Performance Profiling

### Flamegraph

```bash
# Install flamegraph
cargo install flamegraph

# Generate flamegraph
cargo flamegraph --bench vte_parse
```

### Benchmarking

```bash
# Run benchmarks
make bench
```

## Contributing

Before submitting PRs:
1. Run `make check-all` (fmt, clippy, test)
2. Ensure all tests pass
3. Add tests for new features
4. Update documentation as needed

## Next Steps

- Read [debugging.md](debugging.md) for debugging tips
- See [../../docs/reference/](../reference/) for API documentation
- Check [../../docs/explanation/architecture.md](../explanation/architecture.md) for design overview
