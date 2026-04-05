# nix/apps.nix — nix run .#<name> app definitions for kuro
#
# Arguments:
#   pkgs            - nixpkgs for the target system
#   rustToolchain   - stable Rust toolchain (fenix)
#   nightlyToolchain - nightly Rust toolchain (fenix) used for benchmarks
{ pkgs, rustToolchain, nightlyToolchain }:

let
  # Build a nix app from a shell script with pinned runtime dependencies.
  mkApp = name: runtimeInputs: text: {
    type = "app";
    program = "${
        pkgs.writeShellApplication { inherit name runtimeInputs text; }
      }/bin/${name}";
  };

in {
  # Run cargo-tarpaulin coverage report (outputs to stdout).
  # CI uses nix develop --command cargo-tarpaulin for XML output.
  coverage = mkApp "kuro-coverage" [ pkgs.cargo-tarpaulin ] ''
    cargo-tarpaulin --workspace --timeout 300 --out Stdout \
      --include-files rust-core/src/types/color.rs rust-core/src/ffi/codec.rs
  '';

  # Open generated Rust API documentation in the browser.
  doc = mkApp "kuro-doc" [ rustToolchain pkgs.pkg-config ] ''
    cargo doc --workspace --no-deps --open
  '';

  # Build the release library and install it to ~/.local/share/kuro.
  install = mkApp "kuro-install" [ rustToolchain pkgs.pkg-config ] ''
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
  run = mkApp "kuro-run" [ rustToolchain pkgs.pkg-config pkgs.emacs ] ''
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
      --eval "(add-to-list 'load-path \"$REPO_DIR/emacs-lisp\")" \
      --eval "(setenv \"KURO_MODULE_PATH\" \"$REPO_DIR/target/release\")" \
      --eval "(require 'kuro)" \
      --eval "(kuro-create \"/bin/bash\")"
  '';

  # Run criterion benchmarks using the nightly toolchain.
  # nightlyToolchain is in runtimeInputs so its cargo is first on PATH.
  bench = mkApp "kuro-bench" [ nightlyToolchain pkgs.pkg-config ] ''
    cargo bench
  '';
}
