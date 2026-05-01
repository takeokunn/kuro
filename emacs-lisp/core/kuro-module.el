;;; kuro-module.el --- Kuro terminal emulator module definitions  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; This file provides the module definitions and FFI wrappers for the Kuro
;; terminal emulator.  It loads the Rust dynamic module and provides the
;; necessary Lisp functions for interacting with it.

;;; Code:

(require 'kuro-config)  ;; for kuro-module-binary-path defcustom
(require 'url)

(defconst kuro-module--version "1.0.0"
  "Release version string for constructing prebuilt-binary download URLs.")

(defun kuro-module--platform-extension ()
  "Return the platform-specific shared library extension."
  (cond
   ((eq system-type 'gnu/linux) "so")
   ((eq system-type 'darwin) "dylib")
   (t (error "Kuro: Unsupported platform: %s" system-type))))

(defun kuro-module--shared-extension ()
  "Return the shared library file extension with a leading dot.
Delegates to `kuro-module--platform-extension'."
  (concat "." (kuro-module--platform-extension)))

(defun kuro-module--platform-string (&optional system-type-override system-configuration-override)
  "Return the Rust-style target triple for the running Emacs.
SYSTEM-TYPE-OVERRIDE and SYSTEM-CONFIGURATION-OVERRIDE allow tests to inject
specific platform values; when nil they default to the live `system-type'
and `system-configuration' values.

Recognised triples:
  x86_64-unknown-linux-gnu, aarch64-unknown-linux-gnu,
  x86_64-apple-darwin, aarch64-apple-darwin.

Signals an error when the platform cannot be mapped."
  (let* ((stype (or system-type-override system-type))
         (sconf (or system-configuration-override
                    (and (boundp 'system-configuration) system-configuration)
                    ""))
         (aarch64-p (or (string-prefix-p "aarch64" sconf)
                        (string-prefix-p "arm64" sconf))))
    (cond
     ((eq stype 'darwin)
      (if aarch64-p "aarch64-apple-darwin" "x86_64-apple-darwin"))
     ((eq stype 'gnu/linux)
      (if aarch64-p "aarch64-unknown-linux-gnu" "x86_64-unknown-linux-gnu"))
     (t (error "Kuro: unsupported platform: %s" sconf)))))

(defconst kuro-module--known-hashes '()
  "Alist mapping (VERSION . PLATFORM) cons cells to expected SHA256 hex digests.
Each entry takes the form ((VERSION . PLATFORM) . SHA256-HEX).
This table is updated by the release workflow whenever new prebuilt binaries
are published.  When an entry is missing, `kuro-module-download' will warn
and skip integrity verification.")

(defun kuro-module--verify-sha256 (file expected-hash)
  "Return non-nil when FILE matches EXPECTED-HASH (a hex SHA256 digest).
When EXPECTED-HASH is nil, emit a warning via `display-warning' and return t
so that callers can opt in to verification incrementally."
  (cond
   ((null expected-hash)
    (display-warning 'kuro
                     (format "No known SHA256 for %s; skipping verification."
                             file)
                     :warning)
    t)
   (t
    (let ((actual (with-temp-buffer
                    (set-buffer-multibyte nil)
                    (insert-file-contents-literally file)
                    (secure-hash 'sha256 (current-buffer)))))
      (equal actual expected-hash)))))

(defcustom kuro-module-installation-method nil
  "Preferred method for installing the Kuro native module.
When nil, the user is prompted at install time.  Otherwise, must be one of
the symbols `prebuilt' (download from GitHub Releases), `cargo' (build from
source via cargo), or `manual' (the user installs the binary themselves)."
  :group 'kuro
  :type '(choice (const :tag "Prompt" nil)
                 (const :tag "Download prebuilt" prebuilt)
                 (const :tag "Build with cargo" cargo)
                 (const :tag "Manual install" manual)))

(defcustom kuro-module-release-base-url
  "https://github.com/takeokunn/kuro/releases/download"
  "Base URL prefix for constructing prebuilt-artifact download URLs.
Must use the https:// scheme; http:// values are rejected at set time."
  :group 'kuro
  :type 'string
  :set (lambda (sym val)
         (unless (string-prefix-p "https://" val)
           (user-error "Kuro-module-release-base-url must use https://, got: %s" val))
         (set-default sym val)))

(defun kuro-module--target-path ()
  "Return the directory in which prebuilt or cargo-built binaries are installed.
Honours XDG_DATA_HOME when set; otherwise defaults to \"~/.local/share\".
Creates the target directory if it does not yet exist."
  (let* ((xdg (getenv "XDG_DATA_HOME"))
         (base (or xdg "~/.local/share"))
         (dir (expand-file-name "kuro" base)))
    (unless (file-directory-p dir)
      (make-directory dir t))
    dir))

;;;###autoload
(defun kuro-module-download (&optional version)
  "Download a prebuilt libkuro_core matching the current platform.
VERSION is the release tag without the leading \"v\" (defaults to
`kuro-module--version').  The artifact URL is constructed from
`kuro-module-release-base-url' and the platform triple returned by
`kuro-module--platform-string'.

Fetches the accompanying .sha256 sidecar from the same release and
verifies the digest before extraction.  On mismatch, the temp file is
deleted and an error is signalled.  On success, the tarball is extracted
under `kuro-module--target-path' using the system `tar' executable.
Requires `tar' in PATH.  Emacs is unresponsive during the download."
  (interactive)
  (unless (string-prefix-p "https://" kuro-module-release-base-url)
    (error "Kuro: kuro-module-release-base-url must use https://, got: %s"
           kuro-module-release-base-url))
  (let* ((ver (or version kuro-module--version))
         (_ (unless (string-match-p "\\`[0-9]+\\.[0-9]+\\.[0-9]+\\'" ver)
              (error "Kuro: invalid version string: %S" ver)))
         (platform (kuro-module--platform-string))
         (ext (kuro-module--shared-extension))
         (tarball (format "libkuro_core-%s-%s.tar.gz" ver platform))
         (url (format "%s/v%s/%s" kuro-module-release-base-url ver tarball))
         (sha-url (format "%s.sha256" url))
         (target-dir (kuro-module--target-path))
         (tar-bin (executable-find "tar")))
    (unless tar-bin
      (error "Kuro: `tar' executable not found in PATH"))
    (let ((tmp-file (make-temp-file "kuro-module-" nil ".tar.gz")))
      (unwind-protect
          (progn
            (message "Kuro: fetching checksum from %s" sha-url)
            (let* ((sha-buf (url-retrieve-synchronously sha-url t t 30))
                   (expected-hash
                    (progn
                      (unless sha-buf
                        (error "Kuro: failed to fetch SHA256 from %s" sha-url))
                      (unwind-protect
                          (with-current-buffer sha-buf
                            (goto-char (point-min))
                            (unless (re-search-forward "\r?\n\r?\n" nil t)
                              (error "Kuro: malformed SHA256 response from %s" sha-url))
                            (let ((hash (string-trim (buffer-substring (point) (point-max)))))
                              (unless (string-match-p "\\`[0-9a-f]\\{64\\}\\'" hash)
                                (error "Kuro: invalid SHA256 in sidecar response: %S" hash))
                              hash))
                        (kill-buffer sha-buf)))))
              (message "Kuro: downloading %s" url)
              (let ((buffer (url-retrieve-synchronously url t t 300)))
                (unless buffer
                  (error "Kuro: download failed for %s" url))
                (unwind-protect
                    (with-current-buffer buffer
                      (goto-char (point-min))
                      (unless (re-search-forward "\r?\n\r?\n" nil t)
                        (error "Kuro: malformed HTTP response from %s" url))
                      (let ((coding-system-for-write 'binary))
                        (write-region (point) (point-max) tmp-file nil 'silent)))
                  (kill-buffer buffer)))
              (unless (kuro-module--verify-sha256 tmp-file expected-hash)
                (error "Kuro: SHA256 mismatch for %s (expected %s)" url expected-hash))
              (let ((rc (call-process tar-bin nil "*kuro-module-download*" t
                                      "-xzf" tmp-file "-C" target-dir)))
                (delete-file tmp-file)
                (unless (zerop rc)
                  (error "Kuro: tar extraction failed (exit %d, see *kuro-module-download*)" rc))))
            (let ((installed (expand-file-name (concat "libkuro_core" ext) target-dir)))
              (unless (file-exists-p installed)
                (error "Kuro: extracted archive does not contain %s"
                       (concat "libkuro_core" ext)))
              (message "Kuro: installed prebuilt module at %s" installed)
              installed))
        (when (file-exists-p tmp-file)
          (delete-file tmp-file))))))

(defun kuro-module--locate-cargo-toml ()
  "Locate the rust-core/Cargo.toml sibling of the installed package.
Walks up from the directory containing this file looking for a sibling
\"rust-core/Cargo.toml\".  Returns the absolute path on success, nil
otherwise."
  (let* ((this-file (or load-file-name
                        (locate-library "kuro-module")
                        buffer-file-name))
         (dir (and this-file (file-name-directory this-file)))
         (found nil))
    (while (and dir (not found) (not (equal dir (file-name-directory dir))))
      (let ((candidate (expand-file-name "rust-core/Cargo.toml" dir)))
        (if (file-exists-p candidate)
            (setq found candidate)
          (setq dir (file-name-directory (directory-file-name dir))))))
    found))

;;;###autoload
(defun kuro-module-build ()
  "Build libkuro_core from source via cargo.
Requires a development checkout: a sibling rust-core/Cargo.toml must be
reachable from the directory containing this file.  Streams cargo output
to the buffer *kuro-module-build*; on success, copies the produced
libkuro_core into `kuro-module--target-path'."
  (interactive)
  (let ((cargo-toml (kuro-module--locate-cargo-toml)))
    (unless cargo-toml
      (error "Kuro: rust-core not found alongside the package.  Run from a development checkout, or use `M-x kuro-module-download'"))
    (let ((cargo-bin (executable-find "cargo")))
      (unless cargo-bin
        (error "Kuro: `cargo' executable not found in PATH"))
    (let* ((buf (get-buffer-create "*kuro-module-build*"))
           (rc (progn
                 (with-current-buffer buf (erase-buffer))
                 (call-process cargo-bin nil buf t
                               "build" "--release"
                               "--manifest-path" cargo-toml))))
      (unless (zerop rc)
        (pop-to-buffer buf)
        (error "Kuro: cargo build failed (exit %d, see *kuro-module-build*)" rc))
      (let* ((ext (kuro-module--shared-extension))
             (lib-name (concat "libkuro_core" ext))
             (rust-root (file-name-directory cargo-toml))
             (built (expand-file-name (concat "target/release/" lib-name)
                                      rust-root))
             (target-dir (kuro-module--target-path))
             (dest (expand-file-name lib-name target-dir)))
        (unless (file-exists-p built)
          (error "Kuro: cargo reported success but %s is missing" built))
        (copy-file built dest t)
        (message "Kuro: built and installed module at %s" dest)
        dest)))))

(defmacro kuro--module-try (path-expr)
  "Return PATH-EXPR if it names an existing file, nil otherwise."
  `(let ((p ,path-expr))
     (when (and p (file-exists-p p)) p)))

(defun kuro-module--tier-custom ()
  "Tier 1: user-configured path via `kuro-module-binary-path'."
  (kuro--module-try kuro-module-binary-path))

(defun kuro-module--lib-name ()
  "Return the platform-specific shared library filename.
For example: \"libkuro_core.dylib\" on macOS, \"libkuro_core.so\" on Linux."
  (format "libkuro_core.%s" (kuro-module--platform-extension)))

(defun kuro-module--tier-env ()
  "Tier 2: KURO_MODULE_PATH environment variable (treated as a directory)."
  (let* ((lib-name (kuro-module--lib-name))
         (env-dir (getenv "KURO_MODULE_PATH")))
    (kuro--module-try (and env-dir (expand-file-name lib-name env-dir)))))

(defun kuro-module--tier-xdg ()
  "Tier 3: XDG standard install path (~/.local/share/kuro/)."
  (kuro--module-try (expand-file-name (kuro-module--lib-name) "~/.local/share/kuro/")))

(defun kuro-module--tier-dev ()
  "Tier 4: development build output in target/release/ relative to repo root.
`load-file-name' is only set during the initial `load' call; after that
we fall back to `locate-library' so that batch-mode tests also work.
kuro-module.el lives two directories below the repo root (emacs-lisp/core/),
so the path prefix is ../../target/release/."
  (let* ((lib-name (kuro-module--lib-name))
         (this-file (or load-file-name
                        (locate-library "kuro-module")
                        buffer-file-name)))
    (when this-file
      (kuro--module-try
       (expand-file-name
        (format "../../target/release/%s" lib-name)
        (file-name-directory this-file))))))

(defconst kuro-module--search-tiers
  '(kuro-module--tier-custom
    kuro-module--tier-env
    kuro-module--tier-xdg
    kuro-module--tier-dev)
  "Ordered list of module path resolution strategies, tried in priority order.")

(defun kuro-module--find-library ()
  "Find the kuro native module binary via `kuro-module--search-tiers'.
1. kuro-module-binary-path defcustom (user override)
2. KURO_MODULE_PATH environment variable (CI/dev override)
3. XDG standard path: ~/.local/share/kuro/
4. Development fallback: relative to this .el file"
  (seq-some #'funcall kuro-module--search-tiers))

;;;###autoload
(defun kuro-module-load ()
  "Load the kuro native module if available.
Searches for the binary in: custom path, XDG location, development path.
Emits a warning but does not error if the module is not found.
If the module is already loaded (kuro-core-init is fbound), does nothing."
  (unless (fboundp 'kuro-core-init)
    (let ((module-file (kuro-module--find-library)))
      (if (and module-file (file-exists-p module-file))
          (progn
            (message "Kuro: loading module from %s" module-file)
            (module-load module-file))
        (message (substitute-command-keys
                  "Kuro: native module not found. Run \\[kuro-module-download] for a prebuilt binary or \\[kuro-module-build] to compile from source.")
)))))

(defun kuro--ensure-module-loaded ()
  "Load the Rust core module if not already loaded, signalling on failure.
Safe to call multiple times; subsequent calls are no-ops.
Uses `kuro-core-init' fboundp as the authoritative loaded predicate."
  (unless (fboundp 'kuro-core-init)
    (kuro-module-load))
  (unless (fboundp 'kuro-core-init)
    (error (substitute-command-keys
            "Kuro: native module could not be loaded; run \\[kuro-module-download]"))))

(provide 'kuro-module)

;;; kuro-module.el ends here
