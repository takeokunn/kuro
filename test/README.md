# Kuro Test Suite

This directory contains the Emacs Lisp (ERT) test suite for Kuro, organized by test type and functionality.

## Test Structure

```
test/
├── README.md                      # This file
├── kuro-renderer-unit-test.el    # Unit tests for kuro-renderer.el
├── kuro-e2e-test.el             # End-to-end tests (requires Rust module)
├── kuro-config-test.el           # Unit tests for kuro-config.el
└── run-e2e.sh                   # Shell script to run all E2E tests
```

## Test Categories

### 1. Unit Tests (Pure Elisp)

Tests that only require Emacs Lisp and **do not** need the Rust dynamic module (`libkuro_core`).

**Files:**
- `kuro-renderer-unit-test.el` - Tests for `kuro-renderer.el` internal functions
- `kuro-config-test.el` - Tests for `kuro-config.el` validation and setup

**What they test:**
- Render cycle state management
- Cursor positioning and marker handling
- Face caching and application
- Line update operations
- Configuration validation
- Named color mapping

**Running:**

```bash
# Run renderer unit tests only
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro-renderer-unit-test)" \
  --eval "(ert-run-tests-batch-and-exit \"test-kuro\")"

# Run config unit tests only
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro-config-test)" \
  --eval "(ert-run-tests-batch-and-exit \"test-kuro\")"
```

### 2. E2E Tests (Integration)

Tests that require the Rust module to be built and spawn actual PTY sessions. These tests simulate real terminal usage.

**File:**
- `kuro-e2e-test.el` - End-to-end tests covering:
  - Module loading and initialization
  - Basic terminal commands (echo, printf)
  - ANSI colors (16-color, 256-color, TrueColor)
  - Text attributes (bold, underline, inverse, hidden, blink)
  - Terminal resizing
  - Multi-line output
  - Vim compatibility (alternate screen)
  - Mouse encoding (X10, SGR modes)
  - Bracketed paste mode
  - Application cursor keys
  - OSC title sequences

**Prerequisites:**
- Built Rust module: `cargo build --release`
- Shell: `/bin/bash`, `/bin/sh`, or `$SHELL`

**Running:**

```bash
# Run all E2E tests
make test-e2e

# Or manually:
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro)" \
  --eval "(require 'kuro-e2e-test)" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-e2e\")"
```

### 3. Unit Tests in E2E File

`kuro-e2e-test.el` also contains pure unit tests (prefixed with `kuro-unit-`). These test specific functions without needing a live terminal.

**Running:**

```bash
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro)" \
  --eval "(require 'kuro-e2e-test)" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-unit\")"
```

### 4. Rust Tests

For Rust core library tests, see the parent directory:

```bash
# Run all Rust tests
make test
```

### 5. Benchmarks

Performance benchmarks for the Rust core:

```bash
# Run benchmarks (requires nightly Rust)
make bench
```

### 6. Fuzz Tests

Fuzzing tests are located in the `fuzz/` directory. These use AFL-style fuzzing to find edge cases in the VTE parser.

## Running All Tests

The easiest way to run all tests (Rust + Elisp):

```bash
# Run everything
make test-all

# This is equivalent to:
make test           # Rust tests
make test-e2e       # Elisp ERT tests
```

## Running Specific Test Patterns

You can filter tests by name pattern:

```bash
# Run tests matching a pattern
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro-e2e-test)" \
  --eval '(ert-run-tests-batch-and-exit "kuro-e2e-.*color")'

# Run a single test
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro-e2e-test)" \
  --eval '(ert-run-tests-batch-and-exit "^kuro-e2e-echo-command$")'
```

## Test Categories by Functional Area

### Renderer Tests (`kuro-renderer-unit-test.el`)

- **Cycle State Machine** (`test-kuro-render-cycle-*`)
  - Initialization and updates
  - Blink toggling
  - Nil update handling

- **Cursor Updates** (`test-kuro-cursor-*`)
  - Marker positioning
  - Column clamping
  - Visible region handling
  - Type setting

- **Face Application** (`test-kuro-face-*`)
  - Face caching
  - Cache invalidation
  - Face application to buffer
  - Default face handling
  - Attribute decoding

- **Line Updates** (`test-kuro-update-line-*`)
  - Content updates
  - Deletion and insertion
  - Unicode handling
  - Newline preservation

### E2E Tests (`kuro-e2e-test.el`)

- **Module Loading**
  - `kuro-e2e-module-loads` - Verifies FFI functions are available

- **Basic Terminal**
  - `kuro-e2e-terminal-init` - Session initialization
  - `kuro-e2e-echo-command` - Simple command execution
  - `kuro-e2e-multiple-commands` - Sequential commands
  - `kuro-e2e-cursor-position` - Cursor reporting

- **ANSI Colors**
  - `kuro-e2e-ansi-colors` - Basic 16-color support
  - `kuro-e2e-256-color-indexed-fg` - 256-color indexed mode
  - `kuro-e2e-truecolor-rgb-fg` - TrueColor RGB mode
  - `kuro-e2e-bright-color` - Bright color variants

- **Text Attributes**
  - `kuro-e2e-bold-text` - Bold (SGR 1)
  - `kuro-e2e-underline-text` - Underline (SGR 4)
  - `kuro-e2e-background-color` - Background colors
  - `kuro-e2e-inverse-video` - Inverse/reverse video
  - `kuro-e2e-hidden-text` - Hidden/conceal (SGR 8)
  - `kuro-e2e-blink-structural` - Blink attributes

- **Terminal Features**
  - `kuro-e2e-resize` - Terminal resizing
  - `kuro-e2e-no-double-newlines` - No line accumulation
  - `kuro-e2e-clear-command` - Clear screen functionality
  - `kuro-e2e-multiline-output` - Multi-line text handling
  - `kuro-e2e-tab-alignment` - Tab stop handling

- **Application Compatibility**
  - `kuro-e2e-vim-basic` - Vim (alternate screen mode)

### Config Tests (`kuro-config-test.el`)

- **Validation** (`test-kuro-validate-config-*`)
  - Valid configuration
  - Invalid shell paths
  - Invalid scrollback sizes
  - Invalid colors
  - Invalid font sizes
  - Multi-error detection

- **Named Colors** (`test-kuro-rebuild-named-colors-*`)
  - Basic color mapping
  - Color count (16 entries)
  - Custom color updates
  - All color keys present

- **Frame Rate** (`test-kuro-set-frame-rate-*`)
  - Valid frame rates
  - Invalid frame rates (zero/negative)

### Input Tests (in `kuro-e2e-test.el`)

- **Mouse Encoding** (`kuro-unit-mouse-*`)
  - X10 mode (press/release)
  - SGR mode
  - Scroll events
  - Overflow protection

- **Bracketed Paste** (`kuro-unit-yank*`)
  - With and without bracketed paste mode
  - Yank and yank-pop

- **Application Modes** (`kuro-unit-*`)
  - Application cursor keys (DECCKM)
  - Application keypad mode
  - Buffer-local behavior

### Unit Tests (in `kuro-e2e-test.el`)

- **Color Decoding** (`kuro-unit-decode-ffi-color-*`)
  - Default color
  - Named colors (16 basic + 16 bright)
  - Indexed colors (0-255)
  - RGB truecolor

- **Attribute Decoding** (`kuro-unit-decode-attrs-*`)
  - Individual attributes (bold, italic, underline, etc.)
  - Combined attributes
  - All-flags set

- **Title Sanitization** (`kuro-unit-sanitize-title-*`)
  - Clean ASCII
  - Control character stripping
  - BIDI character removal
  - Mixed content handling

## Debugging Failing Tests

### Run Test Verbosely

```bash
# Run with verbose output
emacs --batch -L emacs-lisp -L test \
  --eval "(require 'kuro-e2e-test)" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-e2e\" t)"
```

### Run Test Interactively in Emacs

For faster iteration during development, run tests directly in Emacs:

```elisp
;; Load test files
(add-to-list 'load-path "~/path/to/kuro/emacs-lisp")
(add-to-list 'load-path "~/path/to/kuro/test")

(require 'kuro-e2e-test)

;; Run specific test
(ert-run-tests-interactively "kuro-e2e-echo-command")

;; Run all E2E tests
(ert-run-tests-interactively "kuro-e2e")

;; View test results buffer
(ert-results-switch-to-buffer)
```

### Common Issues

**Issue: "Cannot open shared object file"**
- Solution: Build Rust module first with `cargo build --release`

**Issue: Tests timeout waiting for shell output**
- Solution: Check that your shell (`$SHELL` or `/bin/bash`) is working
- Solution: Increase timeout in test file by modifying `kuro-test--timeout`

**Issue: "Module not found" errors**
- Solution: Ensure `emacs-lisp/` directory is in load path
- Solution: Verify `libkuro_core.so` or `.dylib` exists in `target/release/`

**Issue: Tests fail only in batch mode**
- Solution: Some tests may need interactive mode features. Check test code for `skip-unless` conditions.

**Issue: Vim test fails**
- Solution: Ensure `vim` is installed and in `$PATH`

## Writing New Tests

### Test Naming Convention

- **Unit tests:** `test-<module>-<function>-<behavior>`
  - Example: `test-kuro-face-caching`

- **E2E tests:** `kuro-e2e-<feature>-<scenario>`
  - Example: `kuro-e2e-ansi-colors`

- **Unit tests in E2E file:** `kuro-unit-<function>-<scenario>`
  - Example: `kuro-unit-decode-ffi-color-named-red`

### Test Template

```elisp
(ert-deftest test-kuro-your-function-description ()
  "Brief description of what this test verifies."
  ;; Setup
  (let ((original-value some-variable))
    (unwind-protect
        (progn
          ;; Test body
          (should (equal expected actual)))
      ;; Cleanup
      (setq some-variable original-value))))
```

### E2E Test Template

```elisp
(ert-deftest kuro-e2e-your-feature ()
  "Test that your feature works end-to-end."
  (kuro-test--with-terminal
   ;; Send commands
   (kuro-test--send "your command")
   (kuro-test--send "\r")
   ;; Wait for output
   (should (kuro-test--wait-for buf "expected output"))))
```

## Continuous Integration

All tests run in CI via GitHub Actions. The CI runs:

1. `cargo test --workspace` - Rust tests
2. `cargo clippy --workspace -- -D warnings` - Rust linting
3. `bash test/run-e2e.sh` - Elisp ERT tests

See `.github/workflows/` for CI configuration.

## Coverage

Current test coverage by module:

| Module | Test File | Tests | Coverage |
|--------|-----------|-------|----------|
| `kuro-renderer.el` | `kuro-renderer-unit-test.el` | 21 | Core logic |
| `kuro-config.el` | `kuro-config-test.el` | 26 | Full |
| `kuro-ffi.el` | `kuro-e2e-test.el` (unit) | ~30 | FFI functions |
| `kuro-input.el` | `kuro-e2e-test.el` (unit) | ~40 | Input handling |
| Terminal E2E | `kuro-e2e-test.el` (e2e) | ~170 | Integration |

Total: **287 ERT tests** covering unit, integration, and E2E scenarios.

## Resources

- [ERT Documentation](https://www.gnu.org/software/emacs/manual/html_node/ert/)
- [Emacs Lisp Testing Guide](https://www.gnu.org/software/emacs/manual/html_node/elisp/Testing.html)
- [Kuro Architecture](../docs/architecture.md)
- [Contributing Guide](../CONTRIBUTING.md)
