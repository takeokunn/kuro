;;; kuro-module.el --- Kuro terminal emulator module definitions  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides the module definitions and FFI wrappers for the Kuro
;; terminal emulator. It loads the Rust dynamic module and provides the
;; necessary Lisp functions for interacting with it.

;;; Code:

(require 'kuro-config)  ;; for kuro-module-binary-path defcustom
(require 'kuro-ffi)

(defun kuro-module--platform-extension ()
  "Return the platform-specific shared library extension."
  (cond
   ((eq system-type 'gnu/linux) "so")
   ((eq system-type 'darwin) "dylib")
   (t (error "Kuro: Unsupported platform: %s" system-type))))

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
  "Tier 4: development build output (target/release/ relative to this file).
load-file-name is only set during the initial `load' call; after that
we fall back to locate-library so that batch-mode tests also work."
  (let* ((lib-name (kuro-module--lib-name))
         (this-file (or load-file-name
                        (locate-library "kuro-module")
                        buffer-file-name)))
    (expand-file-name
     (format "../target/release/%s" lib-name)
     (file-name-directory this-file))))

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
      (if (file-exists-p module-file)
          (progn
            (message "Kuro: loading module from %s" module-file)
            (module-load module-file))
        (message "Kuro: native module not found. Run 'make install' to build it. (searched: %s)"
                 module-file)))))

(defvar kuro--module-loaded nil
  "Non-nil if the Rust shared library has been loaded.")

(defun kuro--ensure-module-loaded ()
  "Load the Rust core module if not already loaded.
Safe to call multiple times; subsequent calls are no-ops."
  (unless kuro--module-loaded
    (kuro-module-load)
    (setq kuro--module-loaded t)))

(provide 'kuro-module)

;;; kuro-module.el ends here
