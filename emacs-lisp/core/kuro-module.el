;;; kuro-module.el --- Kuro terminal emulator module definitions  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; This file provides the module definitions and FFI wrappers for the Kuro
;; terminal emulator.  It loads the Rust dynamic module and provides the
;; necessary Lisp functions for interacting with it.

;;; Code:

(require 'kuro-config)  ;; for kuro-module-binary-path defcustom
(require 'kuro-module-platform)
(require 'kuro-module-install)
(require 'kuro-module-macros)

(defun kuro-module--tier-custom ()
  "Tier 1: user-configured path via `kuro-module-binary-path'."
  (kuro--module-try kuro-module-binary-path))

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
      (expand-file-name
       (format "../../target/release/%s" lib-name)
       (file-name-directory this-file)))))

(eval-and-compile
  (defconst kuro-module--search-tiers
    '(kuro-module--tier-custom
      kuro-module--tier-env
      kuro-module--tier-xdg
      kuro-module--tier-dev)
    "Ordered list of module path resolution strategies, tried in priority order."))

(defun kuro-module--find-library ()
  "Find the kuro native module binary via `kuro-module--search-tiers'.
1. kuro-module-binary-path defcustom (user override)
2. KURO_MODULE_PATH environment variable (CI/dev override)
3. XDG standard path: ~/.local/share/kuro/
4. Development fallback: relative to this .el file"
  (kuro--run-module-search-tiers))

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
