;;; kuro-sessions.el --- Session listing UI for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Tabulated session browser for the Kuro terminal emulator.
;;
;; Provides `kuro-list-sessions', a `tabulated-list-mode' buffer
;; that displays all active Kuro sessions (running, detached, dead)
;; with attach, destroy, and refresh commands.

;;; Code:

(require 'cl-lib)
(require 'tabulated-list)

(declare-function kuro-attach "kuro-lifecycle" (session-id))
(declare-function kuro-core-list-sessions "ext:kuro-core" ())
(declare-function kuro-core-shutdown "ext:kuro-core" (session-id))

(defconst kuro--buffer-name-sessions "*kuro-sessions*"
  "Buffer name used by `kuro-list-sessions' to display session list.")

(defconst kuro-sessions--columns
  [("ID" 6 t)
   ("Command" 30 t)
   ("Status" 12 t)]
  "Tabulated columns for `kuro-sessions-mode'.")

(defun kuro--session-status (detached-p alive-p)
  "Return a human-readable status string from DETACHED-P and ALIVE-P flags."
  (cond (detached-p "detached")
        (alive-p    "running")
        (t          "dead")))

(defun kuro-sessions--fetch-raw ()
  "Return the raw session list from the Rust side, or nil on error."
  (condition-case nil
      (kuro-core-list-sessions)
    (error nil)))

(defun kuro-sessions--entry (entry)
  "Convert raw session ENTRY into a `tabulated-list-entries' row."
  (when (and (listp entry) (>= (length entry) 4))
    (pcase-let ((`(,id ,cmd ,detached-p ,alive-p) entry))
      (list id (vector (number-to-string id)
                       cmd
                       (kuro--session-status detached-p alive-p))))))

(defun kuro-sessions--entries ()
  "Return `tabulated-list-entries' for the current Kuro sessions."
  (cl-remove-if #'null
                (mapcar #'kuro-sessions--entry
                        (or (kuro-sessions--fetch-raw) nil))))

(defun kuro-sessions-attach ()
  "Attach to the detached session at point in the sessions buffer."
  (interactive)
  (let ((id (tabulated-list-get-id))
        (entry (tabulated-list-get-entry)))
    (unless id
      (user-error "No session at point"))
    (unless (and entry (string= (aref entry 2) "detached"))
      (user-error "Session %d is not detached" id))
    (kuro-attach id)))

(defun kuro-sessions-destroy ()
  "Destroy the session at point after confirmation."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless id
      (user-error "No session at point"))
    (when (y-or-n-p (format "Destroy session %d? " id))
      (kuro-core-shutdown id)
      (tabulated-list-revert))))

(defun kuro-sessions-refresh ()
  "Refresh the session list."
  (interactive)
  (tabulated-list-revert))

(defvar kuro-sessions-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'kuro-sessions-attach)
    (define-key map (kbd "a")   #'kuro-sessions-attach)
    (define-key map (kbd "d")   #'kuro-sessions-destroy)
    (define-key map (kbd "g")   #'kuro-sessions-refresh)
    (define-key map (kbd "q")   #'quit-window)
    map)
  "Keymap for `kuro-sessions-mode'.")

;;;###autoload
(define-derived-mode kuro-sessions-mode tabulated-list-mode "Kuro Sessions"
  "Major mode for listing Kuro terminal sessions."
  (setq tabulated-list-format kuro-sessions--columns
        tabulated-list-entries #'kuro-sessions--entries
        tabulated-list-padding 2)
  (tabulated-list-init-header))

;;;###autoload
(defun kuro-list-sessions ()
  "Display all active Kuro terminal sessions in a tabulated list buffer."
  (interactive)
  (with-current-buffer (get-buffer-create kuro--buffer-name-sessions)
    (kuro-sessions-mode)
    (tabulated-list-print t)
    (goto-char (point-min)))
  (display-buffer (get-buffer kuro--buffer-name-sessions)))

(provide 'kuro-sessions)

;;; kuro-sessions.el ends here
