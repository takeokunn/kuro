# nix/apps.nix — nix run .#<name> app definitions for kuro
#
# Arguments:
#   pkgs            - nixpkgs for the target system
#   rustToolchain   - stable Rust toolchain (fenix)
#   nightlyToolchain - nightly Rust toolchain (fenix) used for benchmarks
{ pkgs, rustToolchain, nightlyToolchain }:

let
  # Build a nix app from a shell script with pinned runtime dependencies.
  mkApp = name: description: runtimeInputs: text: {
    type = "app";
    program = "${
        pkgs.writeShellApplication { inherit name runtimeInputs text; }
      }/bin/${name}";
    meta = { inherit description; };
  };

in {
  # Run cargo-tarpaulin coverage report (outputs to stdout).
  # CI uses nix develop --command cargo-tarpaulin for XML output.
  coverage = mkApp "kuro-coverage" "Run cargo-tarpaulin coverage report"
    [ pkgs.cargo-tarpaulin ] ''
      cargo-tarpaulin --workspace --timeout 300 --out Stdout \
        --include-files rust-core/src/types/color.rs rust-core/src/ffi/codec.rs
    '';

  # Open generated Rust API documentation in the browser.
  doc =
    mkApp "kuro-doc" "Open generated Rust API documentation in the browser" [
      rustToolchain
      pkgs.pkg-config
    ] ''
      cargo doc --workspace --no-deps --open
    '';

  # Build the release library and install it to ~/.local/share/kuro.
  install =
    mkApp "kuro-install" "Build and install kuro to ~/.local/share/kuro" [
      rustToolchain
      pkgs.pkg-config
    ] ''
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
  run = mkApp "kuro-run" "Build, install, and launch Emacs with kuro loaded" [
    rustToolchain
    pkgs.pkg-config
    pkgs.emacs
  ] ''
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
    mkApp "kuro-bench" "Run criterion benchmarks using the nightly toolchain" [
      nightlyToolchain
      pkgs.pkg-config
    ] ''
      cargo bench
    '';
}
