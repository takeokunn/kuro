;;; kuro-module.el --- Kuro terminal emulator module definitions  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

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

(defun kuro-module--find-library ()
  "Find the kuro native module binary using 4-tier priority.
1. kuro-module-binary-path defcustom (user override)
2. KURO_MODULE_PATH environment variable (CI/dev override)
3. XDG standard path: ~/.local/share/kuro/
4. Development fallback: relative to this .el file"
  (let* ((ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext)))
    (cond
     ;; Tier 1: user-specified custom path
     ((and kuro-module-binary-path (file-exists-p kuro-module-binary-path))
      kuro-module-binary-path)
     ;; Tier 2: KURO_MODULE_PATH environment variable
     ((let ((env-dir (getenv "KURO_MODULE_PATH")))
        (and env-dir
             (file-exists-p (expand-file-name lib-name env-dir))
             (expand-file-name lib-name env-dir))))
     ;; Tier 3: XDG standard install path
     ((file-exists-p (expand-file-name lib-name "~/.local/share/kuro/"))
      (expand-file-name lib-name "~/.local/share/kuro/"))
     ;; Tier 4: development checkout (relative to this file).
     ;; load-file-name is only set during the initial `load' call; after that
     ;; we fall back to locate-library so that batch-mode tests also work.
     (t
      (let* ((this-file (or load-file-name
                            (locate-library "kuro-module")
                            buffer-file-name))
             (dev-path (expand-file-name
                        (format "../target/release/%s" lib-name)
                        (file-name-directory this-file))))
        dev-path)))))

;;;###autoload
(defun kuro-module-load ()
  "Load the kuro native module if available.
Searches for the binary in: custom path, XDG standard location, development path.
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
