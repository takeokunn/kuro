;;; kuro-module.el --- Kuro terminal emulator module definitions  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; This file provides the module definitions and FFI wrappers for the Kuro
;; terminal emulator. It loads the Rust dynamic module and provides the
;; necessary Lisp functions for interacting with it.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-renderer)

;;;###autoload
(defun kuro-module-load ()
  "Load the Kuro Rust dynamic module."
  (let ((module-file
         (cond
          ((eq system-type 'gnu/linux)
           (expand-file-name "target/release/libkuro_core.so"
                             (if (file-directory-p (expand-file-name "../../" (locate-library "kuro-module")))
                                 (expand-file-name "../../" (locate-library "kuro-module"))
                               (expand-file-name "../.." (locate-library "kuro-module")))))
          ((eq system-type 'darwin)
           (expand-file-name "target/release/libkuro_core.dylib"
                             (if (file-directory-p (expand-file-name "../../" (locate-library "kuro-module")))
                                 (expand-file-name "../../" (locate-library "kuro-module"))
                               (expand-file-name "../.." (locate-library "kuro-module")))))
          (t
           (error "Kuro: Unsupported platform")))))
    (when (file-exists-p module-file)
      (module-load module-file)
      (message "Kuro: Loaded module from %s" module-file))))

(kuro-module-load)

(provide 'kuro-module)

;;; kuro-module.el ends here
