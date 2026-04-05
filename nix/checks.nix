# nix/checks.nix — all flake check derivations for kuro
#
# Arguments:
#   pkgs           - nixpkgs for the target system
#   craneLib       - crane library instance (stable toolchain)
#   src            - Rust-filtered source (craneLib.path ./.)
#   elispSrc       - full cleaned source (pkgs.lib.cleanSource ./.)
#   commonArgs     - shared cargo build arguments
#   cargoArtifacts - pre-built dependency artifacts
#   kuro-core      - the main built package (included as a check)
#   advisory-db    - rustsec advisory-db flake input
{ pkgs, craneLib, src, elispSrc, commonArgs, cargoArtifacts, kuro-core
, advisory-db }:

let
  emacs = pkgs.emacs30;

  # Run ERT unit tests (pure Elisp, no Rust module loaded).
  # Mirrors the make test-elisp command exactly.
  #
  # Load order is load-bearing:
  #   1. kuro-test.el  — defines stub replacements for all Rust FFI C-level symbols
  #   2. kuro-performance-test.el — requires kuro-ffi → kuro-renderer-pipeline, safe only after stubs
  #   3. remaining test/unit/*.el — depend on stubs being present
  # Do not reorder these --eval expressions.
  ertCheck = pkgs.stdenv.mkDerivation {
    name = "kuro-elisp-ert";
    src = elispSrc;
    nativeBuildInputs = [ emacs ];
    buildPhase = ''
      emacs -Q --batch \
        -L emacs-lisp \
        -L test/unit \
        --eval "(setq load-prefer-newer t)" \
        --eval "(load (expand-file-name \"test/unit/kuro-test.el\"))" \
        --eval "(load (expand-file-name \"test/integration/kuro-performance-test.el\"))" \
        --eval "(mapc (function load) \
                  (seq-remove \
                    (lambda (f) (string-suffix-p \"/kuro-test.el\" f)) \
                    (directory-files (expand-file-name \"test/unit\") t \"\\.el\$\")))" \
        --eval "(ert-run-tests-batch-and-exit)"
    '';
    installPhase = "touch $out";
  };

  # Byte-compile all Emacs Lisp files; fails on any warning.
  byteCompileCheck = pkgs.stdenv.mkDerivation {
    name = "kuro-byte-compile";
    src = elispSrc;
    nativeBuildInputs = [ emacs ];
    buildPhase = ''
      emacs -Q --batch \
        -L emacs-lisp \
        --eval "(setq byte-compile-error-on-warn t)" \
        --eval "(dolist (f (directory-files \"emacs-lisp\" t \"\\.el\$\")) \
                  (unless (string-match-p \"-pkg\\.el\$\" f) \
                    (unless (byte-compile-file f) \
                      (kill-emacs 1))))"
    '';
    installPhase = "touch $out";
  };

  # Run package-lint on the main entry point.
  packageLintCheck = let
    emacsWithLint = (pkgs.emacsPackagesFor emacs).withPackages
      (epkgs: [ epkgs.package-lint ]);
  in pkgs.stdenv.mkDerivation {
    name = "kuro-package-lint";
    src = elispSrc;
    nativeBuildInputs = [ emacsWithLint ];
    buildPhase = ''
      emacs -Q --batch \
        --eval "(require 'package-lint)" \
        -f package-lint-batch-and-exit \
        emacs-lisp/kuro.el
    '';
    installPhase = "touch $out";
  };

in {
  # Build check — the package itself must build cleanly.
  inherit kuro-core;

  # Rust linting.
  kuro-clippy = craneLib.cargoClippy (commonArgs // {
    inherit cargoArtifacts;
    cargoClippyExtraArgs = "--workspace -- -D warnings";
  });

  # Rust formatting.
  kuro-fmt = craneLib.cargoFmt {
    inherit src;
    pname = "kuro";
    version = "0.1.0";
  };

  # Rust unit + integration tests.
  kuro-test = craneLib.cargoTest (commonArgs // { inherit cargoArtifacts; });

  # Security audit against the rustsec advisory database.
  kuro-audit = craneLib.cargoAudit { inherit src advisory-db; };

  # ERT test suite (Emacs 30).
  kuro-elisp = ertCheck;

  # Byte-compile check (Emacs 30).
  kuro-byte-compile = byteCompileCheck;

  # Package-lint on the main kuro.el entry point (Emacs 30).
  kuro-package-lint = packageLintCheck;
}
