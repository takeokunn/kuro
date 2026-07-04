;;; kuro-tramp.el --- Tramp integration for Kuro terminal  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Integrates the Kuro terminal with Tramp for transparent remote file
;; access.  When the shell is running on a remote host (detected via
;; OSC 7 hostname), `default-directory' is set to a Tramp path so that
;; `find-file', `dired', etc. operate on the remote filesystem.

;;; Code:

(require 'subr-x)
(require 'tramp)
(require 'kuro-config)
(require 'kuro-ffi-osc)

(declare-function kuro--get-cwd-host "kuro-ffi-osc" ())
(declare-function kuro--get-cwd      "kuro-ffi-osc" ())

;;; Customization

(defconst kuro-tramp--allowed-methods '("ssh" "scp" "rsync")
  "TRAMP methods allowed for automatic OSC 7 remote cwd updates.")

(defun kuro-tramp--valid-method-p (method)
  "Return non-nil when METHOD is allowed for automatic TRAMP paths."
  (and (stringp method)
       (member method kuro-tramp--allowed-methods)))

(defun kuro-tramp--set-method (symbol value)
  "Set SYMBOL to VALUE after validating the TRAMP method."
  (unless (kuro-tramp--valid-method-p value)
    (signal 'wrong-type-argument
            (list 'kuro-tramp--valid-method-p value)))
  (set-default symbol value))

(defcustom kuro-tramp-method "ssh"
  "Tramp method used when constructing remote paths from OSC 7.
Only a small method allowlist is accepted because OSC 7 data is
terminal-provided and is used to construct a TRAMP path."
  :type '(choice (const "ssh")
                 (const "scp")
                 (const "rsync"))
  :set #'kuro-tramp--set-method
  :group 'kuro)

(defun kuro-tramp--valid-host-label-p (label)
  "Return non-nil when LABEL is a strict ASCII DNS label."
  (and (stringp label)
       (not (string-empty-p label))
       (<= (string-bytes label) 63)
       (string-match-p
        "\\`[A-Za-z0-9]\\(?:[A-Za-z0-9-]*[A-Za-z0-9]\\)?\\'"
        label)))

(defun kuro-tramp--valid-remote-host-p (host)
  "Return non-nil when HOST is safe for an automatic TRAMP path."
  (and (stringp host)
       (not (string-empty-p host))
       (<= (string-bytes host) 253)
       (let ((labels (split-string host "\\." nil)))
         (and labels
              (catch 'invalid
                (dolist (label labels t)
                  (unless (kuro-tramp--valid-host-label-p label)
                    (throw 'invalid nil))))))))

(defun kuro-tramp--valid-host-list-p (hosts)
  "Return non-nil when HOSTS is a list of strict remote host names."
  (and (listp hosts)
       (catch 'invalid
         (dolist (host hosts t)
           (unless (kuro-tramp--valid-remote-host-p host)
             (throw 'invalid nil))))))

(defun kuro-tramp--set-allowed-hosts (symbol value)
  "Set SYMBOL to VALUE after validating the host allowlist."
  (unless (kuro-tramp--valid-host-list-p value)
    (signal 'wrong-type-argument
            (list 'kuro-tramp--valid-host-list-p value)))
  (set-default symbol value))

(defcustom kuro-tramp-allowed-hosts nil
  "Remote hosts allowed for automatic OSC 7 TRAMP cwd updates.
The default is nil, which denies all remote TRAMP updates.  Entries
are exact host names matched case-insensitively after strict syntax
validation."
  :type '(repeat string)
  :set #'kuro-tramp--set-allowed-hosts
  :group 'kuro)

;;; Core logic

(defun kuro-tramp--safe-absolute-path-p (path)
  "Return non-nil when PATH is a safe absolute local or remote cwd payload."
  (and (stringp path)
       (not (string-empty-p path))
       (string-prefix-p "/" path)
       (not (file-remote-p path))
       (not (string-match-p "[[:cntrl:]]" path))
       (not (string-match-p "[:|]" path))
       (not (string-match-p "\\\\" path))))

(defun kuro-tramp--host-equal-p (left right)
  "Return non-nil when LEFT and RIGHT are the same host ignoring case."
  (and (stringp left)
       (stringp right)
       (string= (downcase left) (downcase right))))

(defun kuro-tramp--local-host-p (host)
  "Return non-nil when HOST names the current machine."
  (and (stringp host)
       (let* ((system-host (system-name))
              (short-system-host
               (and (stringp system-host)
                    (car (split-string system-host "\\." t)))))
         (or (kuro-tramp--host-equal-p host "localhost")
             (kuro-tramp--host-equal-p host system-host)
             (and short-system-host
                  (kuro-tramp--host-equal-p host short-system-host))))))

(defun kuro-tramp--host-allowed-p (host)
  "Return non-nil when HOST is valid and explicitly allowlisted."
  (and (kuro-tramp--valid-remote-host-p host)
       (catch 'found
         (dolist (allowed-host kuro-tramp-allowed-hosts nil)
           (when (kuro-tramp--host-equal-p host allowed-host)
             (throw 'found t))))))

(defun kuro--tramp-remote-path (host path)
  "Construct a Tramp path for HOST and PATH using `kuro-tramp-method'."
  (let ((remote-path (or path "/")))
    (when (and (kuro-tramp--valid-method-p kuro-tramp-method)
               (kuro-tramp--valid-remote-host-p host)
               (kuro-tramp--safe-absolute-path-p remote-path))
      (format "/%s:%s:%s" kuro-tramp-method host remote-path))))

(defun kuro-tramp--target-directory (host cwd)
  "Return the validated directory target for HOST and CWD, or nil."
  (when (kuro-tramp--safe-absolute-path-p cwd)
    (cond
     ((or (null host)
          (and (stringp host) (string-empty-p host)))
      cwd)
     ((not (stringp host))
      nil)
     ((kuro-tramp--local-host-p host)
      cwd)
     ((kuro-tramp--host-allowed-p host)
      (kuro--tramp-remote-path host cwd))
     (t nil))))

(defun kuro--apply-cwd-with-tramp ()
  "Apply CWD from OSC 7, constructing a Tramp path if hostname is remote.
Called from the tier-1 poll instead of the plain `kuro--poll-cwd' when
Tramp integration is desired."
  (when-let* ((cwd (kuro--get-cwd))
              (target (kuro-tramp--target-directory
                       (kuro--get-cwd-host)
                       cwd)))
    (setq default-directory (file-name-as-directory target))))

(provide 'kuro-tramp)

;;; kuro-tramp.el ends here
