;;; kuro-module.el --- Kuro terminal emulator module definitions  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; This file provides the module definitions and FFI wrappers for the Kuro
;; terminal emulator.  It loads the Rust dynamic module and provides the
;; necessary Lisp functions for interacting with it.

;;; Code:

(require 'cl-lib)
(require 'kuro-config)  ;; for kuro-module-binary-path defcustom
(require 'kuro-module-platform)
(require 'kuro-module-install)
(require 'kuro-module-macros)

(cl-defstruct (kuro-module--library-candidate
               (:constructor kuro-module--library-candidate-create)
               (:copier nil))
  (path nil :read-only t)
  (device nil :read-only t)
  (inode nil :read-only t))

(defun kuro-module--library-candidate-error (source path reason)
  "Signal a native module candidate validation error for SOURCE, PATH, REASON."
  (error "Kuro: invalid native module library from %s (%S): %s"
         (or source "module search") path reason))

(defun kuro-module--library-candidate-from-path (path &optional required source)
  "Return a validated native module candidate for PATH.
When REQUIRED is non-nil, missing or empty PATH is an error."
  (let ((origin (or source "module search")))
    (cond
     ((or (not (stringp path)) (= (length path) 0))
      (when required
        (kuro-module--library-candidate-error
         origin path "path must be a non-empty string")))
     ((file-remote-p path)
      (kuro-module--library-candidate-error origin path "path must be local"))
     ((not (equal (file-name-nondirectory path) (kuro-module--lib-name)))
      (kuro-module--library-candidate-error
       origin path (format "basename must be %s" (kuro-module--lib-name))))
     ((file-symlink-p path)
      (kuro-module--library-candidate-error origin path "path must not be a symlink"))
     ((not (file-exists-p path))
      (when required
        (kuro-module--library-candidate-error origin path "file does not exist")))
     (t
      (let ((attrs (file-attributes path 'integer)))
        (unless attrs
          (kuro-module--library-candidate-error
           origin path "attributes are unavailable"))
        (when (car attrs)
          (kuro-module--library-candidate-error
           origin path "file must be a regular file"))
        (unless (= (or (nth 1 attrs) 0) 1)
          (kuro-module--library-candidate-error
           origin path "file must have exactly one link"))
        (let ((modes (file-modes path)))
          (unless (and modes (= (logand modes #o777) #o600))
            (kuro-module--library-candidate-error
             origin path "file mode must be 0600")))
        (kuro-module--library-candidate-create
         :path path
         :device (nth 11 attrs)
         :inode (nth 10 attrs)))))))

(defun kuro-module--library-candidate-active-path (candidate)
  "Return CANDIDATE path after revalidating the same filesystem object."
  (unless (kuro-module--library-candidate-p candidate)
    (error "Kuro: native module library candidate must be typed"))
  (let* ((path (kuro-module--library-candidate-path candidate))
         (current (kuro-module--library-candidate-from-path path t "module load")))
    (unless (and (equal (kuro-module--library-candidate-device current)
                        (kuro-module--library-candidate-device candidate))
                 (equal (kuro-module--library-candidate-inode current)
                        (kuro-module--library-candidate-inode candidate)))
      (error "Kuro: native module library changed before load: %s" path))
    path))

(defun kuro-module--tier-custom ()
  "Tier 1: user-configured path via `kuro-module-binary-path'."
  (when kuro-module-binary-path
    (kuro-module--library-candidate-from-path
     kuro-module-binary-path t "kuro-module-binary-path")))

(defun kuro-module--tier-env ()
  "Tier 2: KURO_MODULE_PATH environment variable (treated as a directory)."
  (let* ((lib-name (kuro-module--lib-name))
         (env-dir (getenv "KURO_MODULE_PATH")))
    (when (and env-dir (> (length env-dir) 0))
      (kuro-module--library-candidate-from-path
       (expand-file-name lib-name env-dir) t "KURO_MODULE_PATH"))))

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

(eval-and-compile
  (defconst kuro-module--search-tiers
    '(kuro-module--tier-custom
      kuro-module--tier-env
      kuro-module--tier-xdg
      kuro-module--tier-dev)
    "Ordered list of module path resolution strategies, tried in priority order."))

(defun kuro-module--find-library ()
  "Find a validated kuro native module candidate via search tiers.
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
    (let ((candidate (kuro-module--find-library)))
      (if candidate
          (let ((module-file
                 (kuro-module--library-candidate-active-path candidate)))
            (message "Kuro: loading module from %s" module-file)
            (module-load module-file))
        (message (substitute-command-keys
                  "Kuro: native module not found. Run \\[kuro-module-download] for a prebuilt binary or \\[kuro-module-build] to compile from source."))))))

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
