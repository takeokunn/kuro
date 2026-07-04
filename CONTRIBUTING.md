# Contributing to Kuro

Thank you for your interest in contributing!

## Development Setup

### With Nix (recommended)

Kuro uses a full [Nix](https://nixos.org/download)-based workflow. The dev shell
provides the pinned Rust toolchain, Emacs, and all tooling:

```bash
git clone https://github.com/takeokunn/kuro.git
cd kuro
nix develop            # Rust toolchain + Emacs + cargo-tarpaulin on PATH
```

### Without Nix

- **Rust** 1.84.0 or later (MSRV): https://rustup.rs
- **Emacs** 29.4 or later, built with module support
  (`brew install emacs`, `apt install emacs`, `pacman -S emacs`, …)
- A C toolchain (`build-essential` / `xcode-select --install`)

Verify Emacs has module support:

```bash
emacs --batch --eval "(unless (fboundp 'module-load) (error \"No module support\"))"
```

### Build from source

```bash
# Development build (faster, less optimized)
cargo build --workspace

# Release build (optimized)
cargo build --release --workspace

# Output lands in the workspace target dir at the repo root:
#   target/release/libkuro_core.so      (Linux)
#   target/release/libkuro_core.dylib   (macOS)

# Or, with Nix — build + install to ~/.local/share/kuro:
nix run .#install
```

### Loading the module in Emacs

```elisp
(add-to-list 'load-path "~/path/to/kuro/emacs-lisp/core")
(require 'kuro)        ; pulls in the sibling modules and the native module
(kuro-create "bash")
```

`M-x kuro-module-build` compiles the native module from source via cargo;
`M-x kuro-module-download` fetches a prebuilt binary for your platform.

### Hot-reload workflow

- **Elisp change**: re-evaluate the file (`M-x eval-buffer`, or
  `M-x load-file`).
- **Rust change**: rebuild, then reload the module in Emacs:

  ```bash
  cargo build --release --workspace
  ```
  ```elisp
  (unload-feature 'kuro t)
  (require 'kuro)
  ```

## Testing

Run the full check suite exactly as CI does:

```bash
nix flake check        # Rust tests + ERT (Emacs 29.4 & 30.1) + byte-compile
                       # + clippy -D warnings + fmt + package-lint + audit
```

Or run pieces directly:

```bash
# Rust unit + integration tests
cargo test --manifest-path rust-core/Cargo.toml

# Elisp ERT unit suite (pure Elisp, no native module) — see test/README.md
# for the canonical multi-`-L` invocation.

# End-to-end tests (spawn a PTY — run outside the Nix sandbox)
nix develop --command bash test/scripts/runners/run-e2e.sh
```

See [test/README.md](test/README.md) for the test layout, the exact ERT
command, and conventions. New code should keep coverage high and must not
regress existing tests.

## Code style

```bash
cargo fmt --all                                              # Rust formatting
cargo clippy --manifest-path rust-core/Cargo.toml --workspace -- -D warnings
nix fmt                                                       # Rust + Nix (treefmt)
```

- **Rust**: `rustfmt` + clippy clean (`-D warnings`); prefer
  `#[expect(lint, reason = "…")]` over `#[allow]`.
- **Elisp**: byte-compiles cleanly (`nix flake check` enforces zero warnings)
  and passes `package-lint`.
- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/).

## Development workflow

1. Branch: `git checkout -b feat/your-feature`
2. Write tests alongside the code.
3. Run `nix flake check` until green.
4. Open a PR with a descriptive title and summary.

## Troubleshooting

**"Cannot open shared object file"**
- Confirm the module exists: `ls -la target/release/libkuro_core.*`
- Verify Emacs was built with module support (`(fboundp 'module-load)`).

**"Function not defined" / FFI symbol missing**
- Confirm the module loaded: `(featurep 'kuro-module)` should be `t`.
- Rebuild after Rust changes and reload (`unload-feature` then `require`).

**"Failed to spawn PTY"**
- Verify the shell exists (`which bash`) and you can allocate a PTY.

**Module works once, then fails**
- Global state wasn't reset — `(unload-feature 'kuro t)` before reloading.

## Project structure

```
kuro/
├── rust-core/             # Rust cdylib (the terminal core)
│   ├── src/
│   │   ├── types/         # Color, Cell, Cursor, SGR, OSC types
│   │   ├── grid/          # Screen, Line, scrollback
│   │   ├── parser/        # VT100/CSI/OSC/DCS/Sixel/Kitty parsing
│   │   ├── pty/           # POSIX PTY management
│   │   └── ffi/           # Emacs module bridge + session management
│   └── tests/             # Integration tests (external crate)
├── emacs-lisp/            # Emacs Lisp display layer
│   ├── core/              # kuro.el, kuro-config, kuro-lifecycle, kuro-module
│   ├── ffi/               # FFI bridge, binary decoder, OSC plumbing
│   ├── rendering/         # renderer pipeline, overlays, render-buffer
│   ├── input/             # keymap, mouse, input dispatch
│   ├── faces/             # face construction, palette, attributes
│   └── features/          # stream, sessions, navigation, prompt-status
├── test/                  # Elisp ERT tests (see test/README.md)
└── nix/                   # flake checks, apps, formatter config
```

## Getting help

- **Issues**: bug reports and feature requests
- **Discussions**: questions and ideas

## Code review

1. CI (`nix flake check`) must pass.
2. At least one maintainer approval.
3. Tests must pass and coverage must not regress.
