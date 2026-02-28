{
  description = "Kuro - High-performance terminal emulator for Emacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs = { self, nixpkgs, fenix, crane }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          rustToolchain = fenix.packages.${system}.stable.toolchain;
          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
          src = craneLib.path ./.;
          commonArgs = {
            inherit src;
            pname = "kuro";
            version = "0.1.0";
            strictDeps = true;
            buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];
            nativeBuildInputs = [ pkgs.pkg-config ];
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          kuro-core = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });
        in
        {
          default = kuro-core;
          inherit kuro-core;
        });

      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          rustToolchain = fenix.packages.${system}.stable.toolchain;
          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
          src = craneLib.path ./.;
          commonArgs = {
            inherit src;
            pname = "kuro";
            version = "0.1.0";
            strictDeps = true;
            buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];
            nativeBuildInputs = [ pkgs.pkg-config ];
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          kuro-core = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });
        in
        {
          inherit kuro-core;

          kuro-clippy = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--workspace -- -D warnings";
          });

          kuro-fmt = craneLib.cargoFmt { inherit src; pname = "kuro"; version = "0.1.0"; };

          kuro-test = craneLib.cargoTest (commonArgs // {
            inherit cargoArtifacts;
          });
        });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          rustToolchain = fenix.packages.${system}.stable.withComponents [
            "cargo"
            "clippy"
            "rust-src"
            "rustc"
            "rustfmt"
          ];
        in
        {
          default = pkgs.mkShell {
            packages = [
              rustToolchain
              pkgs.emacs
              pkgs.cargo-tarpaulin
              pkgs.pkg-config
            ];
            shellHook = ''
              cat <<USAGE_EOF

=== Kuro Development Shell ===

Automated checks:
  nix flake check        # Run all checks (build + clippy + fmt + test) in sandbox
  make dev               # Debug build
  make build             # Release build (generates .so for Emacs)
  make test              # Run Rust test suite
  make lint              # Run Clippy (warnings as errors)
  make check             # Check rustfmt formatting
  make check-all         # fmt + lint + test

Manual testing in Emacs:
  make build
  emacs -Q \\
    --eval "(add-to-list 'load-path \"$PWD/emacs-lisp\")" \\
    --eval "(setenv \"KURO_MODULE_PATH\" \"$PWD/target/release\")" \\
    --eval "(require 'kuro)" \\
    --eval "(kuro-create)"

Phase 2 acceptance tests (run inside kuro buffer):
  echo "Hello World"              # Test 1: basic text output
  printf "line1\nline2\n"         # Test 2: multi-line
  printf "\tindented"             # Test 3: tab alignment
  echo -e "\a"                    # Test 4: BEL notification (ding)
  printf '%200s\n' | tr ' ' 'x'  # Test 5: long line wrap

USAGE_EOF
            '';
          };
        });
    };
}
