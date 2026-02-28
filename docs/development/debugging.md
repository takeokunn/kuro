# Debugging Guide

This guide covers debugging techniques for Kuro's Rust core and Emacs integration.

## Table of Contents

- [Rust Debugging](#rust-debugging)
- [Emacs Debugging](#emacs-debugging)
- [FFI Issues](#ffi-issues)
- [PTY Problems](#pty-problems)
- [VTE Parser Debugging](#vte-parser-debugging)
- [Performance Profiling](#performance-profiling)

## Rust Debugging

### Logging

Add logging to your Rust code:

```rust
use log::{info, debug, error};

pub fn parse_vte(&mut self, bytes: &[u8]) {
    debug!("Received {} bytes", bytes.len());
    // ... parsing logic
    info!("Parsing complete");
}
```

Enable logging with environment variable:
```bash
RUST_LOG=debug cargo run
```

### Using GDB

1. Build with debug symbols:
```bash
cargo build
```

2. Run under GDB:
```bash
gdb --args target/debug/kuro-test
```

3. Useful GDB commands:
```gdb
break grid::screen::Screen::update_cell
run
bt    # backtrace
p variable_name  # print variable
continue
```

### Using LLDB (macOS)

```bash
lldb target/debug/kuro-test
(lldb) breakpoint set --name grid::screen::Screen::update_cell
(lldb) run
(lldb) bt
```

### Panic Debugging

When Rust panics in FFI context:
1. Set `RUST_BACKTRACE=1`
2. The panic message will include a backtrace
3. Common causes:
   - Null pointers from Emacs
   - Wrong type conversions
   - Unhandled `Err` values with `?` operator

## Emacs Debugging

### Elisp Debugging

#### Using `M-x toggle-debug-on-error`

```elisp
(setq debug-on-error t)
;; Run code that errors
;; Emacs will show backtrace
```

#### Using `M-x edebug`

Instrument a function:
```elisp
(require 'edebug)
(defun kuro--render-cycle ()
  (interactive)
  (edebug-defun)  ; Instrument this function
  ;; ... function body
  )
```

Then call `M-x kuro--render-cycle` and step through with:
- `SPC` - Step through
- `n` - Next expression
- `c` - Continue
- `q` - Quit

### Viewing FFI Calls

Add logging to `emacs-lisp/kuro-ffi.el`:

```elisp
(defun kuro--poll-updates ()
  (message "[KURO] Polling for updates...")
  (let ((result (kuro-core-poll-updates)))
    (message "[KURO] Got %d dirty lines" (length result))
    result))
```

### Tracing Buffer Modifications

```elisp
(add-hook 'after-change-functions
          (lambda (start end len)
            (when (eq major-mode 'kuro-mode)
              (message "Buffer changed: %d-%d (deleted %d chars)"
                       start end len))))
```

## FFI Issues

### Type Mismatches

Common symptoms:
- Emacs crashes on function call
- Garbage data returned
- "Wrong type argument" errors

Debug checklist:
1. Verify `#[defun]` signature matches Elisp call
2. Check `FromLisp` and `IntoLisp` trait implementations
3. Ensure user-ptr is correctly initialized

Example debugging:
```rust
#[defun]
fn kuro_test_function(input: String) -> Result<String> {
    eprintln!("[FFI] Called with: {:?}", input);  // Debug to stderr
    Ok(input)
}
```

### Memory Issues

#### User-ptr Not Initialized

```elisp
;; Wrong: calling before init
(kuro-core-poll-updates)  ; Error: user-ptr is None

;; Correct: initialize first
(kuro-core-init "bash")
(kuro-core-poll-updates)  ; Works
```

#### Memory Leaks

Use Valgrind (Linux) or Instruments (macOS):

```bash
# Linux
valgrind --leak-check=full --show-leak-kinds=all emacs

# macOS
instruments -t "kuro.trace" --template "Leaks" emacs
```

### Catching Panics

All FFI functions should use `catch_unwind`:

```rust
use std::panic;

#[defun]
fn kuro_safe_function() -> Result<String> {
    panic::catch_unwind(|| {
        // Code that might panic
        Ok("success".to_string())
    }).map_err(|_| "Panic occurred".to_string())?
}
```

## PTY Problems

### PTY Not Opening

Symptoms:
- `kuro-create` returns error
- Shell doesn't start

Debugging:
```rust
// In pty/posix.rs
eprintln!("[PTY] Opening PTY master...");
let master = posix_openpt(O_RDWR)?;
eprintln!("[PTY] Master fd: {}", master);

eprintln!("[PTY] Granting unlock...");
grantpt(&master)?;
eprintln!("[PTY] Unlocking...");
unlockpt(&master)?;
```

### Shell Not Responding

Check PTY communication:
```rust
// Write test byte
pty.write_all(b"echo test\n")?;

// Wait and read
use std::thread;
use std::time::Duration;
thread::sleep(Duration::from_millis(100));

let mut buf = [0u8; 1024];
let n = pty.read(&mut buf)?;
eprintln!("[PTY] Read: {}", String::from_utf8_lossy(&buf[..n]));
```

### Signal Handling

Verify signal handlers are installed:
```rust
eprintln!("[SIGNAL] Installing SIGCHLD handler...");
// Set up handler
eprintln!("[SIGNAL] Handler installed");
```

## VTE Parser Debugging

### Logging VTE Sequences

```rust
impl vte::Perform for TerminalCore {
    fn print(&mut self, c: char) {
        eprintln!("[VTE] Print: '{}'", c);
        // ...
    }

    fn execute(&mut self, byte: u8) {
        eprintln!("[VTE] Execute: 0x{:02x}", byte);
        // ...
    }

    fn csi_dispatch(&mut self, params: &vte::Params, intermediates: &[u8], ignore: bool, c: char) {
        eprintln!("[VTE] CSI: params={:?}, char={}", params, c);
        // ...
    }
}
```

### Test Specific Sequences

```rust
#[test]
fn test_sgr_colors() {
    let mut terminal = TerminalCore::new(24, 80);
    let input = b"\x1b[31mRed text\x1b[0m";
    terminal.advance(input);
    // Check state
    assert!(terminal.screen.cursor.attrs.foreground == Color::Named(NamedColor::Red));
}
```

## Performance Profiling

### Flamegraph

```bash
# Install
cargo install flamegraph

# Profile a specific benchmark
cargo flamegraph --bench vte_parse
```

### Criterion Benchmarks

```rust
// benches/vte_parse.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_vte_parse(c: &mut Criterion) {
    let input = b"\x1b[31mRed\x1b[0m";
    c.bench_function("vte_parse_sgr", |b| {
        b.iter(|| {
            let mut parser = vte::Parser::new();
            let mut handler = TestHandler::new();
            for byte in input {
                parser.advance(&mut handler, *byte);
            }
        });
    });
}

criterion_group!(benches, bench_vte_parse);
criterion_main!(benches);
```

### CPU Profiler (Linux)

```bash
# Run with perf
perf record -g cargo test

# Analyze
perf report
```

### Instruments (macOS)

```bash
# Build release
cargo build --release

# Run with Instruments
instruments -t "kuro_cpu.trace" \
    --template "Time Profiler" \
    target/release/kuro-test
```

## Common Issues and Solutions

### Issue: "Module load failed"

**Cause**: Compiled module incompatible with Emacs

**Solution**:
1. Verify Emacs version compatibility (29.1+)
   ```bash
   emacs --version
   ```
2. Rebuild module: `make clean && make build`
3. Check module format matches platform:
   - Linux: `.so`
   - macOS: `.dylib`
   - Windows: `.dll`
4. Verify dynamic library dependencies:
   ```bash
   # Linux
   ldd target/release/libkuro_core.so

   # macOS
   otool -L target/release/libkuro_core.dylib
   ```

### Issue: "Function not defined"

**Cause**: Module not loaded or function not exported

**Solution**:
```elisp
;; Check module is loaded
(featurep 'kuro-module)  ; Should return t

;; List exported functions
(apropos "kuro-")

;; Check if init was called
(if (fboundp 'kuro-core-init)
    (message "Module loaded")
  (message "Module not loaded"))
```

### Issue: High CPU usage

**Cause**: Render loop too fast or PTY reader spinning

**Solution**:
1. Reduce frame rate:
   ```elisp
   M-x customize-variable RET kuro-frame-rate
   ;; Set to 30 or 60 FPS
   ```
2. Check PTY reader uses blocking read
3. Profile to find bottleneck (see Performance Profiling section)

### Issue: Garbage in buffer

**Cause**: Binary data or UTF-8 decode error

**Solution**:
```rust
// In rust-core/src/ffi/abstraction.rs
// Filter non-printable characters
let output: String = bytes
    .iter()
    .filter(|&&b| b >= 0x20 || b == b'\n' || b == b'\r' || b == b'\t')
    .map(|&b| b as char)
    .collect();
```

### Issue: "PTY spawn failed"

**Cause**: Shell command not found or permission denied

**Solution**:
```elisp
;; Check if shell exists
(which "bash")  ; Should return path

;; Try a different shell
(kuro-create "/bin/sh")

;; Check error message
(kuro-create "bash")
;; Look in *Messages* buffer for details
```

### Issue: "Version mismatch: Emacs 28.x is incompatible"

**Cause**: Emacs version is too old

**Solution**:
```bash
# Check current version
emacs --version

# Upgrade to Emacs 29.1+
# macOS
brew install emacs

# Ubuntu
sudo apt install emacs

# Build from source with module support
git clone https://git.savannah.gnu.org/git/emacs.git
cd emacs
./autogen.sh
./configure --with-modules
make
sudo make install
```

### Issue: Module works once, then fails on reload

**Cause**: Global state not reset properly

**Solution**:
```elisp
;; Always shutdown before reloading
(kuro-kill)

;; Then reload module
(unload-feature 'kuro)
(require 'kuro)

;; Create new terminal
(kuro-create "bash")
```

### Issue: "State error: No terminal session"

**Cause**: Trying to use terminal before initialization

**Solution**:
```elisp
;; Always initialize first
(kuro-core-init "bash")

;; Then you can use other functions
(kuro-core-poll-updates)
(kuro-core-send-key [?\C-l])
```

### Issue: Intermittent crashes on resize

**Cause**: Race condition in PTY resize

**Solution**:
1. Increase debounce timeout in kuro-resize
2. Check for multiple concurrent resize calls
3. Verify PTY is still open before resize
```elisp
;; Check if terminal is alive
(if (kuro-core-get-scrollback-count)
    (kuro-resize 24 80)
  (message "Terminal not active"))
```

### Issue: Colors not displaying correctly

**Cause**: Terminal doesn't support 256 colors or RGB

**Solution**:
```bash
# Check terminal capability
tput colors

# In Emacs, check terminal type
(getenv "TERM")
;; Should be xterm-256color or similar
```

### Issue: Performance degradation over time

**Cause**: Memory leak or buffer growth

**Solution**:
1. Check scrollback buffer size:
   ```elisp
   M-x customize-variable RET kuro-scrollback-size
   ```
2. Limit scrollback to reasonable size (e.g., 10000 lines)
3. Check for memory leaks:
   ```bash
   # Linux
   valgrind --leak-check=full emacs

   # macOS
   instruments -t "kuro.trace" --template "Leaks" emacs
   ```

### Issue: Unicode characters display as ?

**Cause**: Font doesn't support unicode or locale issues

**Solution**:
```elisp
;; Check font setup
(font-family-list)

;; Set a unicode-compatible font
(set-face-attribute 'default nil :family "Fira Code" :height 120)

;; Check locale in shell
;; Run in kuro terminal:
locale
```

### Issue: Keys not passing through correctly

**Cause**: Emacs keybindings interfering

**Solution**:
```elisp
;; Check keybindings
C-h k  ;; Then press the key

;; Add to kuro-mode-map if needed
(define-key kuro-mode-map (kbd "<C-tab>") 'self-insert-command)
```

### Issue: Cursor position incorrect

**Cause**: Screen state desynchronized

**Solution**:
```elisp
;; Force screen refresh
(kuro-render)

;; Check cursor position
(kuro-core-get-cursor)
```

### Issue: Module loads but FFI calls fail

**Cause**: ABI mismatch or symbol not found

**Solution**:
```bash
# Check exported symbols
nm target/release/libkuro_core.so | grep kuro

# Verify symbol naming matches
nm -D target/release/libkuro_core.so | grep -i init
```

### Issue: Build fails on WSL2

**Cause**: Different toolchain or dependencies

**Solution**:
```bash
# Update WSL2
wsl --update

# Ensure build tools are installed
sudo apt update
sudo apt install build-essential

# Rebuild in WSL2 environment
cargo clean
cargo build --release
```

## Getting Help

If debugging tips don't solve your issue:

1. Check existing GitHub issues
2. Create a minimal reproduction case
3. Include:
   - OS and Emacs version
   - Rust version (`rustc --version`)
   - Error messages and backtraces
   - Minimal code example
4. Tag with `debugging` label
