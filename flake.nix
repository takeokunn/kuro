{
  description = "Kuro - High-performance terminal emulator for Emacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, fenix, crane, advisory-db, treefmt-nix }:
    let
      supportedSystems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      mkKuro = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          rustToolchain = fenix.packages.${system}.stable.toolchain;
          nightlyToolchain = fenix.packages.${system}.latest.toolchain;
          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
          src = craneLib.path ./.;
          elispSrc = pkgs.lib.cleanSource ./.;
          commonArgs = {
            inherit src;
            pname = "kuro";
            version = "0.1.0";
            strictDeps = true;
            buildInputs =
              pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];
            nativeBuildInputs = [ pkgs.pkg-config ];
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          kuro-core =
            craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });
        in {
          inherit pkgs craneLib src elispSrc commonArgs cargoArtifacts kuro-core
            rustToolchain nightlyToolchain;
        };

      # Shared treefmt evaluation — produces both formatter and check.
      mkTreefmt = system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system}
        (import ./nix/treefmt.nix);
    in {
      # nix fmt — format Nix files (nixfmt via treefmt).
      # Rust formatting is checked by `kuro-fmt` in `nix flake check`.
      formatter =
        forAllSystems (system: (mkTreefmt system).config.build.wrapper);

      packages = forAllSystems (system:
        let ctx = mkKuro system;
        in {
          default = ctx.kuro-core;
          inherit (ctx) kuro-core;
        });

      checks = forAllSystems (system:
        let ctx = mkKuro system;
        in (import ./nix/checks.nix {
          inherit (ctx)
            pkgs craneLib src elispSrc commonArgs cargoArtifacts kuro-core;
          inherit advisory-db;
        }) // {
          # Verify that all Nix files are formatted (treefmt).
          treefmt = (mkTreefmt system).config.build.check self;
        });

      apps = forAllSystems (system:
        let ctx = mkKuro system;
        in import ./nix/apps.nix {
          inherit (ctx) pkgs rustToolchain nightlyToolchain;
        });

      devShells = forAllSystems (system:
        let
          ctx = mkKuro system;
          pkgs = ctx.pkgs;
          stableShell = fenix.packages.${system}.stable.withComponents [
            "cargo"
            "clippy"
            "rust-src"
            "rustc"
            "rustfmt"
          ];
          darwinInputs =
            pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];
        in {
          # Default development shell — stable Rust + Emacs + tarpaulin.
          default = pkgs.mkShell {
            packages = [
              stableShell
              pkgs.emacs
              pkgs.cargo-tarpaulin
              pkgs.pkg-config
              pkgs.rust-analyzer
              pkgs.cargo-audit
              pkgs.cargo-watch
            ];
            shellHook = ''
                            cat <<'EOF'

              === Kuro Development Shell ===

                nix fmt                  # Format Nix files (treefmt/nixfmt)
                nix flake check          # All checks (Rust + ERT + byte-compile + audit + treefmt)
                nix build                # Release build
                nix run .#coverage       # Code coverage (stdout)
                nix run .#doc            # Open Rust docs
                nix run .#install        # Install to ~/.local/share/kuro
                nix run .#run            # Build + install + launch Emacs
                nix run .#bench          # Criterion benchmarks (nightly Rust)
                nix develop --command bash test/scripts/runners/run-e2e.sh  # E2E (PTY, outside sandbox)
                nix develop .#fuzz --command bash -c "cd rust-core/fuzz && cargo fuzz run advance"

              EOF
            '';
          };

          # Fuzz shell — nightly Rust + cargo-fuzz for libFuzzer targets.
          fuzz = pkgs.mkShell {
            packages = [ ctx.nightlyToolchain pkgs.cargo-fuzz pkgs.pkg-config ]
              ++ darwinInputs;
            shellHook = ''
              echo "Kuro fuzz shell (nightly Rust + cargo-fuzz)"
              echo "  cd rust-core/fuzz && cargo fuzz run advance -- -max_total_time=30 -runs=1000"
            '';
          };
        });
    };
}
