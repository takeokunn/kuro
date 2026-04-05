# nix/apps.nix — nix run .#<name> app definitions for kuro
#
# Arguments:
#   pkgs             - nixpkgs for the target system (nixos-25.11)
#   rustToolchain    - stable Rust toolchain (fenix)
#   nightlyToolchain - nightly Rust toolchain (fenix) used for benchmarks
#   llvmTools        - stable LLVM tools component (fenix) used for llvm-cov
#   cargoLlvmCov     - cargo-llvm-cov from nixpkgs-unstable (0.6.20 in 25.11 is broken)
{
  pkgs,
  rustToolchain,
  nightlyToolchain,
  llvmTools,
  cargoLlvmCov,
}:

let
  # Build a nix app from a shell script with pinned runtime dependencies.
  mkApp = name: description: runtimeInputs: text: {
    type = "app";
    program = "${pkgs.writeShellApplication { inherit name runtimeInputs text; }}/bin/${name}";
    meta = { inherit description; };
  };

in
{
  # Run cargo-llvm-cov workspace coverage (fails if line coverage drops below 90%).
  # Excludes code that requires OS-level or Emacs runtime context:
  #   src/ffi/bridge/**       — all #[defun] entry points (require Emacs module runtime)
  #   src/lib.rs              — #[emacs::module] plugin entry point (requires module loader)
  #   src/ffi/test_terminal.rs — ERT test helper (called from Emacs, not Rust)
  #   src/ffi/fallback.rs     — raw C API placeholder stubs (no production callers)
  #   src/pty/posix.rs        — fork/openpty/exec boundary (requires real PTY process)
  coverage =
    mkApp "kuro-coverage" "Run llvm-cov workspace coverage (fails if line coverage < 90%)"
      [
        cargoLlvmCov
        llvmTools
      ]
      ''
        cargo llvm-cov --workspace \
          --ignore-filename-regex \
            'src/ffi/bridge/|src/lib\.rs|src/ffi/test_terminal\.rs|src/ffi/fallback\.rs|src/pty/posix\.rs' \
          --lcov --output-path lcov.info \
          --fail-under-lines 90
      '';

  # Open generated Rust API documentation in the browser.
  doc =
    mkApp "kuro-doc" "Open generated Rust API documentation in the browser"
      [
        rustToolchain
        pkgs.pkg-config
      ]
      ''
        cargo doc --workspace --no-deps --open
      '';

  # Build the release library and install it to ~/.local/share/kuro.
  install =
    mkApp "kuro-install" "Build and install kuro to ~/.local/share/kuro"
      [
        rustToolchain
        pkgs.pkg-config
      ]
      ''
        INSTALL_DIR="$HOME/.local/share/kuro"
        cargo build --release
        if [[ "$(uname -s)" == "Darwin" ]]; then
          LIB="libkuro_core.dylib"
        else
          LIB="libkuro_core.so"
        fi
        mkdir -p "$INSTALL_DIR"
        cp "target/release/$LIB" "$INSTALL_DIR/$LIB"
        echo "Kuro: installed $LIB to $INSTALL_DIR"
      '';

  # Build, install, and launch Emacs with kuro loaded.
  run =
    mkApp "kuro-run" "Build, install, and launch Emacs with kuro loaded"
      [
        rustToolchain
        pkgs.pkg-config
        pkgs.emacs
      ]
      ''
        INSTALL_DIR="$HOME/.local/share/kuro"
        cargo build --release
        if [[ "$(uname -s)" == "Darwin" ]]; then
          LIB="libkuro_core.dylib"
        else
          LIB="libkuro_core.so"
        fi
        mkdir -p "$INSTALL_DIR"
        cp "target/release/$LIB" "$INSTALL_DIR/$LIB"
        REPO_DIR="$(pwd)"
        exec emacs -Q \
          --eval "(add-to-list 'load-path \"$REPO_DIR/emacs-lisp/core\")" \
          --eval "(setenv \"KURO_MODULE_PATH\" \"$REPO_DIR/target/release\")" \
          --eval "(require 'kuro)" \
          --eval "(kuro-create \"/bin/bash\")"
      '';

  # Run criterion benchmarks using the nightly toolchain.
  # nightlyToolchain is in runtimeInputs so its cargo is first on PATH.
  bench =
    mkApp "kuro-bench" "Run criterion benchmarks using the nightly toolchain"
      [
        nightlyToolchain
        pkgs.pkg-config
      ]
      ''
        cargo bench
      '';
}
