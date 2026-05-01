;;; kuro-tramp.el --- Tramp integration for Kuro terminal  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Integrates the Kuro terminal with Tramp for transparent remote file
;; access.  When the shell is running on a remote host (detected via
;; OSC 7 hostname), `default-directory' is set to a Tramp path so that
;; `find-file', `dired', etc. operate on the remote filesystem.

;;; Code:

(require 'tramp)
(require 'kuro-config)
(require 'kuro-ffi-osc)

(declare-function kuro--get-cwd-host "kuro-ffi-osc" ())
(declare-function kuro--get-cwd      "kuro-ffi-osc" ())

;;; Customization

(defcustom kuro-tramp-method "ssh"
  "Tramp method used when constructing remote paths from OSC 7.
Common choices: \"ssh\", \"scp\", \"rsync\"."
  :type 'string
  :group 'kuro)

;;; Core logic

(defun kuro--tramp-remote-path (host path)
  "Construct a Tramp path for HOST and PATH using `kuro-tramp-method'."
  (format "/%s:%s:%s" kuro-tramp-method host (or path "/")))

(defun kuro--apply-cwd-with-tramp ()
  "Apply CWD from OSC 7, constructing a Tramp path if hostname is remote.
Called from the tier-1 poll instead of the plain `kuro--poll-cwd' when
Tramp integration is desired."
  (when-let ((cwd (kuro--get-cwd)))
    (when (and (stringp cwd) (not (string-empty-p cwd)))
      (let ((host (kuro--get-cwd-host)))
        (setq default-directory
              (file-name-as-directory
               (if host
                   (kuro--tramp-remote-path host cwd)
                 cwd)))))))

(provide 'kuro-tramp)

;;; kuro-tramp.el ends here
