;;; kuro-lifecycle-module.el --- Native module installation helpers for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; This file contains the runtime helpers for checking, prompting for, and
;; installing the Kuro native module.

;;; Code:

(require 'kuro-module)

(eval-and-compile
  (defconst kuro--module-install-methods
    '((prebuilt ?d kuro-module-download "download")
      (cargo    ?b kuro-module-build    "cargo build"))
    "Auto-install methods as (SYMBOL KEY-CHAR INSTALL-FN DISPLAY-NAME).
Each entry maps a `kuro-module-installation-method' symbol and an
interactive key character to the install function and its display name.")

  (defmacro kuro--install-module-by-method (method)
    "Dispatch METHOD directly to the matching installer."
    `(pcase ,method
       ,@(mapcar (lambda (entry)
                   `((quote ,(nth 0 entry))
                     (kuro--install-and-load-module #',(nth 2 entry)
                                                    ,(nth 3 entry))))
                 kuro--module-install-methods)
       ('manual (user-error "Native module missing; install manually then retry"))
       (_ (kuro--prompt-and-install-module))))

  (defmacro kuro--install-module-by-key (key)
    "Dispatch KEY directly to the matching installer."
    `(pcase ,key
       ,@(mapcar (lambda (entry)
                   `(,(nth 1 entry)
                     (kuro--install-and-load-module #',(nth 2 entry)
                                                    ,(nth 3 entry))))
                 kuro--module-install-methods)
       (_ (user-error "Aborted: kuro native module is required")))))

(defun kuro--module-loadable-p ()
  "Return non-nil when the Rust dynamic module is loaded into Emacs.
Detects this by probing for `kuro-core-init', the canonical FFI entry
point provided by the native module."
  (fboundp 'kuro-core-init))

(defun kuro--try-load-module ()
  "Attempt to load the Rust native module, swallowing any errors.
Returns non-nil iff the module is loaded after the attempt."
  (ignore-errors (kuro-module-load))
  (kuro--module-loadable-p))

(defun kuro--install-and-load-module (install-fn install-name)
  "Run INSTALL-FN, load the module, and verify it's callable.
INSTALL-NAME is a display string used in the error message on failure.
Signals an error when the module is not loadable after installation."
  (funcall install-fn)
  (kuro-module-load)
  (or (kuro--module-loadable-p)
      (error "Kuro: %s succeeded but native init is not bound" install-name)))

(defun kuro--prompt-and-install-module ()
  "Prompt the user to choose an install method from `kuro--module-install-methods'.
Reads a single character: one of the KEY-CHARs in the methods table or `q'
to abort.  Dispatches through `kuro--install-module-by-key' on a match,
or signals `user-error' for `q'."
  (let* ((valid-keys (append (mapcar (lambda (m) (nth 1 m))
                                     kuro--module-install-methods)
                             '(?q)))
         (key (read-char-choice
               (concat "Kuro native module not found. "
                       "Install: [d]ownload prebuilt, [b]uild from source, [q]uit? ")
               valid-keys)))
    (kuro--install-module-by-key key)))

(defun kuro--ensure-module-installed ()
  "Ensure the native module is installed, prompting the user if not.
Honours `kuro-module-installation-method': symbols in
`kuro--module-install-methods' map to their install functions directly;
`manual' aborts with an error; nil falls through to the interactive prompt.
Returns non-nil on success; signals an error otherwise."
  (or (kuro--try-load-module)
      (kuro--install-module-by-method kuro-module-installation-method)))

(provide 'kuro-lifecycle-module)
;;; kuro-lifecycle-module.el ends here
