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
{
  pkgs,
  craneLib,
  src,
  elispSrc,
  commonArgs,
  cargoArtifacts,
  kuro-core,
}:

let
  emacs = pkgs.emacs30;

  # Run ERT unit tests (pure Elisp, no Rust module loaded).
  #
  # Load order is load-bearing:
  #   1. kuro-test-stubs.el — canonical Rust FFI stubs (required by kuro-test.el)
  #   2. kuro-test.el       — loads kuro.el and defines ERT tests for kuro.el
  #   3. remaining test/unit/**/*.el — depend on stubs being present
  # Do not reorder these --eval expressions.
  ertCheck = pkgs.stdenv.mkDerivation {
    name = "kuro-elisp-ert";
    src = elispSrc;
    nativeBuildInputs = [ emacs ];
    buildPhase = ''
      emacs -Q --batch \
        -L emacs-lisp/core \
        -L test/unit \
        -L test/unit/core \
        -L test/unit/ffi \
        -L test/unit/rendering \
        -L test/unit/input \
        -L test/unit/faces \
        -L test/unit/features \
        --eval "(setq load-prefer-newer t)" \
        --eval "(load (expand-file-name \"test/unit/core/kuro-test.el\"))" \
        --eval "(mapc (function load) \
                  (seq-remove \
                    (lambda (f) (string-suffix-p \"/kuro-test.el\" f)) \
                    (directory-files-recursively (expand-file-name \"test/unit\") \"\\.el\$\")))" \
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
        -L emacs-lisp/core \
        --eval "(require 'kuro)" \
        --eval "(setq byte-compile-error-on-warn t)" \
        --eval "(dolist (f (directory-files-recursively \"emacs-lisp\" \"\\.el\$\")) \
                  (unless (string-match-p \"-pkg\\.el\$\" f) \
                    (unless (byte-compile-file (expand-file-name f)) \
                      (kill-emacs 1))))"
    '';
    installPhase = "touch $out";
  };

  # Run package-lint on user-facing entry points.
  #
  # kuro.el is the main package file. The two secondary files contain
  # autoloaded user-facing commands (`kuro-start`, `kuro-sessions`) and benefit
  # from package-lint coverage. Pure helpers (faces, renderer pipeline, …) are
  # excluded — they are internal implementation, not entry points.
  #
  # Secondary files lack their own `Package-Requires:` headers (intentional —
  # the dependency set lives in kuro.el). The wrapper sets
  # `package-lint-main-file` so package-lint treats kuro.el as authoritative
  # and does not re-flag the missing headers in the secondary files.
  packageLintCheck =
    let
      emacsWithLint = (pkgs.emacsPackagesFor emacs).withPackages (epkgs: [ epkgs.package-lint ]);
    in
    pkgs.stdenv.mkDerivation {
      name = "kuro-package-lint";
      src = elispSrc;
      nativeBuildInputs = [ emacsWithLint ];
      buildPhase = ''
        emacs -Q --batch \
          --eval "(require 'package-lint)" \
          --eval "(setq package-lint-main-file \"emacs-lisp/core/kuro.el\")" \
          -f package-lint-batch-and-exit \
          emacs-lisp/core/kuro.el \
          emacs-lisp/core/kuro-lifecycle.el \
          emacs-lisp/features/kuro-sessions.el
      '';
      installPhase = "touch $out";
    };

  # Run checkdoc on every Emacs Lisp file under emacs-lisp/.
  #
  # Failure mode: checkdoc-current-buffer collects diagnostics in a buffer
  # whose name we control. After processing each file we read the buffer
  # contents; if non-empty, we print them and increment an error counter.
  # Derivation exits non-zero iff any file produced a diagnostic.
  #
  # `kuro-pkg.el` is excluded defensively (auto-generated style file, may
  # reappear). Test files under test/ are not checked.
  checkdocCheck = pkgs.stdenv.mkDerivation {
    name = "kuro-checkdoc";
    src = elispSrc;
    nativeBuildInputs = [ emacs ];
    buildPhase = ''
      emacs -Q --batch \
        -L emacs-lisp/core \
        --eval "(require 'checkdoc)" \
        --eval "(let ((errors 0) \
                      (diag-buffer \"*kuro-checkdoc-diag*\")) \
                  (dolist (file (directory-files-recursively \"emacs-lisp\" \"\\.el\$\")) \
                    (unless (string-match-p \"-pkg\\.el\$\" file) \
                      (when (get-buffer diag-buffer) \
                        (let ((kill-buffer-query-functions nil)) \
                          (kill-buffer diag-buffer))) \
                      (with-temp-buffer \
                        (insert-file-contents file) \
                        (setq buffer-file-name file) \
                        (emacs-lisp-mode) \
                        (let ((checkdoc-diagnostic-buffer diag-buffer)) \
                          (ignore-errors (checkdoc-current-buffer t)))) \
                      (when (get-buffer diag-buffer) \
                        (let ((output (with-current-buffer diag-buffer (buffer-string)))) \
                          (when (and output (string-match-p \":[0-9]+:\" output)) \
                            (princ (format \"==> %s\n%s\n\" file output)) \
                            (setq errors (1+ errors))))))) \
                  (kill-emacs (if (zerop errors) 0 1)))"
    '';
    installPhase = "touch $out";
  };

in
{
  # Build check — the package itself must build cleanly.
  inherit kuro-core;

  # Rust linting.
  kuro-clippy = craneLib.cargoClippy (
    commonArgs
    // {
      inherit cargoArtifacts;
      cargoClippyExtraArgs = "--workspace -- -D warnings";
    }
  );

  # Rust formatting.
  kuro-fmt = craneLib.cargoFmt {
    inherit src;
    pname = "kuro";
    version = "0.1.0";
  };

  # Rust unit + integration tests.
  kuro-test = craneLib.cargoTest (commonArgs // { inherit cargoArtifacts; });

  # ERT test suite (Emacs 30).
  kuro-elisp = ertCheck;

  # Byte-compile check (Emacs 30).
  kuro-byte-compile = byteCompileCheck;

  # Package-lint on user-facing entry points (Emacs 30).
  kuro-package-lint = packageLintCheck;

  # Checkdoc across all Emacs Lisp source files (Emacs 30).
  kuro-checkdoc = checkdocCheck;
}
