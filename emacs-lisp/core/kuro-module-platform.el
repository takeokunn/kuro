;;; kuro-module-platform.el --- Platform helpers for Kuro native module  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Shared platform and path helpers for the Kuro native module.

;;; Code:

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

(defun kuro-module--lib-name ()
  "Return the platform-specific shared library filename.
For example: \"libkuro_core.dylib\" on macOS, \"libkuro_core.so\" on Linux."
  (format "libkuro_core.%s" (kuro-module--platform-extension)))

(provide 'kuro-module-platform)
;;; kuro-module-platform.el ends here
