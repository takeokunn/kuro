# Coverage Measurement

## Overview

`cargo-tarpaulin` is used to measure Rust unit test coverage for the `rust-core` crate.

Coverage measurement applies to **unit tests only**. The compiled `.so`/`.dylib` dynamic module is loaded by an external Emacs process at runtime, so E2E tests (driven by the Emacs Lisp test suite) run outside the Rust process and cannot be instrumented by tarpaulin. E2E test results are qualitative pass/fail — they supplement coverage data but are not included in tarpaulin reports.

## Per-Module Coverage Targets

| Module      | Target  |
|-------------|---------|
| `parser/`   | ≥ 90%   |
| `grid/`     | ≥ 85%   |
| `types/`    | ≥ 85%   |
| `pty/`      | ≥ 65%   |
| `ffi/`      | ≥ 65%   |
| **Overall** | **≥ 80%** |

### FFI Layer

The `ffi/` module sits at the boundary between Rust and Emacs. Its coverage target is lower (≥ 65%) because the most meaningful validation of FFI correctness comes from the E2E Elisp tests, which exercise the full call path through the dynamic module. Those tests report pass/fail and are not measured by tarpaulin.

## Running Coverage

```bash
cargo tarpaulin --exclude-files "fuzz/*" --out Html
```

The `fuzz/` directory must be excluded because fuzz targets require nightly Rust. Including them in a stable build invocation will cause a compilation failure.

The HTML report is written to `tarpaulin-report.html` in the current directory.

## Fuzz Testing

Fuzz targets live in `rust-core/fuzz/` and are managed as a separate Cargo workspace. The root `Cargo.toml` contains `exclude = ["fuzz"]` so that nightly-only fuzz code never interferes with stable builds.

There are four fuzz targets:

| Target              | Description                              |
|---------------------|------------------------------------------|
| `fuzz_advance`      | VT/ANSI sequence parser (main input loop) |
| `fuzz_kitty_params` | Kitty terminal protocol parameter parsing |
| `fuzz_apc_payload`  | APC escape sequence payload handling     |
| `fuzz_decode_png`   | PNG image data decoding (Kitty graphics) |

To run a fuzz target for 30 seconds:

```bash
cargo +nightly fuzz run fuzz_advance -- -max_total_time=30
```

Replace `fuzz_advance` with any of the four target names listed above.

Fuzz targets are intentionally excluded from tarpaulin coverage reports because they require a nightly toolchain and a libFuzzer-linked binary, neither of which is compatible with tarpaulin's instrumentation under the stable toolchain.
