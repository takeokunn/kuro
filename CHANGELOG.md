# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- OSC 133 extras: `aid=`, `duration=`, `err=` kv pairs and positional exit code on D-mark for richer shell-integration job tracking (FR-115).
- DA3 (Tertiary Device Attributes) response: reply to `CSI = c` with `DCS ! | 00000000 ST`, completing the DA1/DA2/DA3 triad (FR-117).
- DEC private mode 2031 (`color_scheme_notifications`) and DSR 996: terminal answers `CSI ? 996 n` with `CSI ? 997 ; 1 n` and proactively emits color-scheme change notifications when mode 2031 is set (FR-119).
- OSC 133 prompt extras (aid, duration, err path) are now surfaced to Emacs via the extended 7-tuple returned by `kuro-core-poll-prompt-marks` and rendered as end-of-line annotations by the `kuro-prompt-status` feature. Gated by `kuro-prompt-status-show-extras` (default t). New face `kuro-prompt-extras` (FR-124).
- Automatic dark/light theme bridge: Emacs's `enable-theme-functions` is debounced and forwarded to `kuro-core-set-color-scheme`, so DSR 996 queries and DEC private mode 2031 notifications reflect the real Emacs theme. New defcustom `kuro-color-scheme-debounce-seconds`, autoload `M-x kuro-color-scheme-refresh` (FR-125).
- `.elpaignore` for clean package distribution (excludes Rust, tests, docs from package)
- `package-lint` CI step for MELPA compliance validation
- Module availability detection in E2E tests (`kuro-test--module-loaded`)

### Changed

- **Breaking for downstream hooks**: `kuro-core-poll-prompt-marks` now returns 7-tuples `(MARK-TYPE ROW COL EXIT-CODE AID DURATION-MS ERR-PATH)` instead of 4-tuples. Consumers that read positions 0–3 via `nth` or `pcase` rest patterns are unaffected. Consumers using closed-arity `pcase` patterns (e.g. `` `(,t ,r ,c ,e) mark ``) must migrate to the rest pattern `` `(,t ,r ,c ,e . ,_) mark ``.

### Fixed

- 40 ERT unit test failures: `kuro-core-send-key` stubs updated from 1-arg to 2-arg `(_sid bytes)` to match multi-session FFI signature
- 93 E2E tests marked `:expected-result :failed` when Rust module not loaded (previously errored unexpectedly)
- 7 cargo doc warnings: escaped `<bool>`, `[R,G,B]`, `#[defun]` and private item links
- CI ERT test step now uses `make test-elisp` (was referencing nonexistent `test/elisp/` directory)
- CI cargo doc step enforces zero-warning policy
- `set_winsize()` TIOCSWINSZ ioctl return value now checked (was silently ignored)
- Code formatting applied via `cargo fmt --all`

## Previously in [Unreleased]

### Added

- **ESC M (RI — Reverse Index)**: moves cursor up one line; scrolls down when at top of scroll region. Enables correct `less`, `man`, and vim reverse-scroll behavior.
- **ESC D (IND — Index)**: moves cursor down one line, scrolling up at bottom of scroll region. Completes the vertical motion ESC set.
- **ESC E (NEL — Next Line)**: combined CR+LF in a single escape sequence. Required for correct ANSI compliance.
- `KURO_MODULE_PATH` environment variable support (Tier 2 in 4-tier module discovery): enables CI and development override without `make install`.
- `test/vttest-compliance.sh`: runs VTE compliance tests and reports pass rate against 80% target (no PTY required).
- `test/bench-validate.sh`: runs criterion benchmarks and validates >100 MB/s parse throughput target.
- `make test-safe`: new Makefile target running only unit tests that are safe inside tmux/opencode sessions (no PTY spawning).
- `make vttest-compliance`: convenience target for VTE compliance check.
- `make bench-validate`: convenience target for throughput benchmark validation.
- 11 new VTE compliance tests in `vt_compliance.rs`: RI, IND, NEL, scroll region restriction, HVP, ED3 (erase scrollback), SGR invisible/strikethrough, CUP boundary clamping, IL/DL operations.
- 5 new property-based tests in `lib.rs` proptest block: SGR reset invariant, CUP boundary clamping, ESC M no-panic, large input cursor bounds, combined attribute reset.
- 5 new unit tests for ESC M/D/E edge cases (no-underflow, scroll at top, basic movement).

### Fixed

- Removed `tmux kill-session` trap from `test/run-e2e.sh` that could kill the user's outer tmux session.
- 23 Clippy warnings (`needless_borrows_for_generic_args`, `op_ref`) fixed across `bridge.rs` and `lib.rs`.
- Code formatting applied via `cargo fmt`.

## [1.0.0] - 2026-03-01

### Added

**Terminal Emulation**

- PTY management via the `nix` crate: fork/exec shell process with non-blocking reads and process lifecycle handling
- Terminal grid state: `Screen`, `Cell`, and `Cursor` types with dirty-set tracking for incremental rendering
- C0 control character processing: CR, LF, BS, HT, BEL with visual bell notification
- Auto-wrap mode (DECAWM, `?7h/l`) and line-wrap-on-overflow behavior
- CSI cursor movement sequences: CUU, CUD, CUF, CUB, CUP, VPA, CHA, HVP with boundary clamping
- Erase sequences: ED (erase display, modes 0/1/2) and EL (erase line, modes 0/1/2)
- SGR attribute parsing: bold, dim, italic, underline, blink-slow, blink-fast, inverse, hidden, strikethrough, and reset
- ANSI 16-color support (foreground 30–37/90–97, background 40–47/100–107) with correct RGB values
- 256-color indexed support (`38;5;n`, `48;5;n`) and 24-bit TrueColor RGB support (`38;2;r;g;b`, `48;2;r;g;b`)
- DEC private modes: DECCKM (`?1`), DECTCEM (`?25`), DECAWM (`?7`), alternate screen buffer (`?1049` smcup/rmcup)
- ESC sequences: DECSC/DECRC cursor save/restore, RIS (full reset)
- Scroll region support (DECSTBM) and SU/SD scroll-up/scroll-down operations
- Line insert/delete (IL/DL) and character insert/delete/erase (ICH/DCH/ECH) sequences
- OSC 0/2 window title sequences and OSC 8 hyperlink protocol
- Bracketed paste mode (`?2004`)
- Application cursor key mode (DECCKM) and keypad application/numeric mode (DECKPAM/DECKPNM)
- Unicode full-width character support using the `unicode-width` crate; CJK characters occupy two grid cells with placeholder cell for correct cursor positioning
- Combining character (zero-width) and emoji width handling
- Scrollback buffer (`ScrollbackBuffer`) with configurable size (default 10,000 lines) and automatic LRU trimming
- Real-time full-screen update support for `top`/`htop` with frame-drop handling under high-frequency output
- tmux support: pane splitting, window management, session lifecycle
- Kitty Graphics Protocol: APC sequence parsing (`ESC _ ... ESC \`), Base64 payload decoding, PNG/RGB/RGBA format support, `GraphicsStore` with LRU eviction, and grid-based image placement

**Emacs Integration**

- `kuro-module` dynamic module bridge exposing `kuro-core-new`, `kuro-core-poll-updates`, `kuro-core-clear-dirty`, `kuro-core-send-key`, and related FFI functions via `emacs-module-rs`
- 30 fps timer-driven render loop (`kuro--render-loop`) with dirty-row polling and incremental buffer updates
- `kuro--make-face` and `kuro--apply-faces` for mapping Rust color/attribute data to Emacs face plists using `add-text-properties`
- Face cache to avoid redundant face object allocation on repeated color values
- Blink overlay implementation for SGR 5 (slow blink, ~0.5 Hz) and SGR 6 (fast blink, ~1.5 Hz) via frame-counter modulo switching
- `invisible` text property for SGR 8 (hidden) applied outside face plist
- Inverse-video (SGR 7) foreground/background swap in face construction
- Full keyboard mapping table (Emacs key events to PTY byte sequences): arrow keys, function keys F1–F12, modifier combinations (Ctrl, Alt/Meta, Shift), Home/End/PageUp/PageDown
- `kuro-input` module handling self-insert characters and special key dispatch
- `kuro-renderer` module for buffer rendering, cursor display, and window resize propagation
- Image rendering via Emacs `create-image` for Kitty Graphics Protocol payloads
- Scrollback navigation keybindings (Shift+PageUp/PageDown)

**Configuration System**

- `kuro-config` module with `defcustom` variables: `kuro-shell`, `kuro-scrollback-size`, `kuro-font-family`, `kuro-font-size`, `kuro-module-binary-path` (custom binary path override), and `kuro-color-*` palette overrides
- Validation functions for all user options
- Runtime reconfiguration support without restarting the terminal
- Emacs customize group `kuro` for interactive configuration via `M-x customize-group`

**Testing Infrastructure**

- Rust unit test suite targeting 80%+ code coverage across parser, grid, FFI, and PTY modules
- Property-based tests using `proptest` for parser and grid state invariants
- Fuzz testing for the VTE parser against malformed byte sequences
- Elisp ERT test suite covering renderer, input handling, configuration, and FFI bridge integration
- End-to-end test suite (`kuro-e2e-test.el`) validating full terminal session behavior
- Multi-platform CI testing: Linux (glibc and musl), macOS (Intel x86_64 and Apple Silicon ARM)

**Release Infrastructure**

- MELPA recipe preparation and `package.el`-compatible packaging
- Pre-built `.so` / `.dylib` release artifacts for Linux glibc, Linux musl, macOS x86_64, and macOS ARM64
- CI/CD pipeline for automated build, test, and release artifact generation
- `cargo-audit` integration for dependency vulnerability scanning
- vttest compliance at 80%+ pass rate

### Changed

- Rust crate restructured from module-per-directory layout (`ffi/mod.rs`, `grid/mod.rs`, `parser/mod.rs`, `pty/mod.rs`) to flat module files (`ffi.rs`, `grid.rs`, `parser.rs`, `pty.rs`) for simpler navigation
- FFI bridge refactored into `ffi/abstraction.rs` and `ffi/bridge.rs` separation for cleaner Emacs module boundary
- Parser extended with `insert_delete.rs` and `kitty.rs` sub-modules to handle IL/DL/ICH/DCH and Kitty APC sequences respectively
- `kuro.el` updated to load and coordinate `kuro-config`, `kuro-input`, `kuro-module`, and `kuro-renderer` sub-modules

### Security

- All `unsafe` blocks in the FFI bridge documented with explicit safety invariants
- `cargo-audit` run against the full dependency tree; no known vulnerabilities in v1.0.0 release dependencies
- PTY file descriptor handling reviewed for correct ownership and close-on-exec behavior

### Fixed

- Cursor boundary clamping corrected to prevent out-of-bounds grid writes when sequences specify positions beyond terminal dimensions
- Scrollback buffer trimming no longer drops lines below the configured limit under rapid output conditions
- Face cache invalidation fixed to correctly reflect color theme changes applied at runtime
