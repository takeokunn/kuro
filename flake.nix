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

      mkKuro = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
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
        in
        {
          inherit pkgs craneLib src commonArgs cargoArtifacts;
          kuro-core = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });
        };
    in
    {
      packages = forAllSystems (system:
        let ctx = mkKuro system; in
        {
          default = ctx.kuro-core;
          inherit (ctx) kuro-core;
        });

      checks = forAllSystems (system:
        let ctx = mkKuro system; in
        {
          inherit (ctx) kuro-core;

          kuro-clippy = ctx.craneLib.cargoClippy (ctx.commonArgs // {
            inherit (ctx) cargoArtifacts;
            cargoClippyExtraArgs = "--workspace -- -D warnings";
          });

          kuro-fmt = ctx.craneLib.cargoFmt {
            inherit (ctx) src;
            pname = "kuro";
            version = "0.1.0";
          };

          kuro-test = ctx.craneLib.cargoTest (ctx.commonArgs // {
            inherit (ctx) cargoArtifacts;
          });
        });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
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
              cat <<'USAGE_EOF'

=== Kuro Development Shell ===

  make run                 # Build + install + launch as macOS GUI app
  make build               # Release build
  make test                # Run Rust test suite
  make test-elisp          # Run ERT test suite
  make lint                # Clippy (warnings as errors)
  make check-all           # fmt + lint + test
  nix flake check          # All checks in sandbox

USAGE_EOF
            '';
          };
        });
    };
}
