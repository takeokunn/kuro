# Kuro Test Suite

This directory holds the Emacs Lisp (ERT) tests for Kuro. The Rust core has its
own tests under [`rust-core/`](../rust-core) (see the table at the bottom).

## Layout

```
test/
├── unit/                 # Pure-Elisp ERT unit tests — no Rust module required
│   ├── core/             #   kuro.el, kuro-config, kuro-lifecycle, kuro-module, …
│   ├── ffi/              #   FFI bridge, binary decoder, OSC plumbing, eval allowlist
│   ├── rendering/        #   renderer pipeline, overlays, render-buffer, typewriter
│   ├── input/            #   keymap, mouse, input dispatch
│   ├── faces/            #   face construction, palette, attributes
│   └── features/         #   stream, sessions, navigation, prompt-status, …
├── e2e/                  # End-to-end tests — spawn a real PTY (need the built module)
└── scripts/
    ├── runners/          # run-e2e.sh, vttest-compliance.sh
    ├── benchmarks/       # bench-validate.sh, kuro-daemon-debug.sh
    └── stress/           # interactive stress scripts (colors, TUI, comprehensive)
```

The unit tests are **pure Elisp**: they stub the Rust FFI (`kuro-test-stubs.el`)
and never load `libkuro_core`, so they run anywhere Emacs does. The e2e tests
spawn an actual shell over a PTY and require the native module to be built.

## Running

### Everything (recommended)

```bash
nix flake check
```

Runs the Rust unit + integration tests, the ERT suite on Emacs 30, byte-compilation,
`clippy -D warnings`, `cargo fmt --check`, `package-lint`, `checkdoc`, and `treefmt`
formatting validation — the same checks CI runs.

### The ERT unit suite directly

The load order is load-bearing: `test/unit/core/kuro-test.el` installs the FFI
stubs and loads `kuro.el`, so it must load **first**; the remaining files are
then loaded and all `ert-deftest`s run together.

```bash
emacs -Q --batch \
  -L emacs-lisp/core -L test/unit -L test/unit/core -L test/unit/ffi \
  -L test/unit/rendering -L test/unit/input -L test/unit/faces -L test/unit/features \
  --eval "(setq load-prefer-newer t)" \
  --eval "(load (expand-file-name \"test/unit/core/kuro-test.el\"))" \
  --eval "(mapc #'load \
            (seq-remove (lambda (f) (string-suffix-p \"/kuro-test.el\" f)) \
              (directory-files-recursively (expand-file-name \"test/unit\") \"\\.el$\")))" \
  --eval "(ert-run-tests-batch-and-exit)"
```

Filter to a subset by passing a selector regexp to
`ert-run-tests-batch-and-exit`, e.g. `"^kuro-renderer-"` or
`"^kuro-input-mouse-"`.

### End-to-end tests (PTY — run outside the Nix sandbox)

```bash
nix develop --command bash test/scripts/runners/run-e2e.sh
```

These build the release module, spawn real shells, and exercise colors,
attributes, resize, alternate screen, mouse encoding, bracketed paste, and OSC
sequences end-to-end.

### VTE compliance

```bash
nix develop --command bash test/scripts/runners/vttest-compliance.sh
```

## Conventions

- **File names**: unit test files end in `-test.el`; shared fixtures live in
  `*-test-support.el` and are loaded by the files that need them. Split a large
  file by descriptive area (e.g. `kuro-input-mouse-test.el`), not numeric
  `-ext` suffixes.
- **Test names**: `kuro-<area>-<behavior>` for unit tests (e.g.
  `kuro-renderer-pipeline-apply-dirty-lines-...`); `kuro-e2e-<feature>` for e2e.
- **No real module in unit tests**: rely on the stubs in `kuro-test-stubs.el`;
  add a stub there if your code calls a new `kuro-core-*` FFI function.

## Writing a unit test

```elisp
(ert-deftest kuro-config-validate-rejects-bad-scrollback ()
  "kuro--validate-config flags a non-positive scrollback size."
  (let ((kuro-scrollback-size -1))
    (should (kuro--validate-config))))   ; returns the list of problems
```

## Rust tests

```bash
nix flake check                         # includes Rust unit + integration tests
cargo test --manifest-path rust-core/Cargo.toml   # just the Rust tests, locally
cargo clippy --manifest-path rust-core/Cargo.toml --workspace -- -D warnings
nix run .#bench                         # criterion benchmarks (nightly Rust)
```

| Layer | Location | Notes |
|-------|----------|-------|
| Rust unit | `rust-core/src/**/tests/` | same crate; `pub(crate)` items visible |
| Rust integration | `rust-core/tests/` | external crate; only `pub` items visible |
| Elisp unit | `test/unit/` | pure Elisp, FFI stubbed |
| Elisp e2e | `test/e2e/` | real PTY, needs the built module |
