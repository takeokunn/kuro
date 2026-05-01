;;; kuro-dnd.el --- Drag-and-drop support for Kuro terminal buffers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:
;; Handles drag-and-drop events in Kuro terminal buffers.
;; Dropping a file inserts its shell-quoted path into the terminal,
;; making it easy to reference files in shell commands.

;;; Code:

(require 'dnd)

(declare-function kuro--send-key "kuro-ffi" (data))

(defun kuro-dnd-handle-uri (uri _action)
  "Handle a drag-and-drop URI by inserting the file path into the terminal.
URI is a file:// URL.  The path is shell-quoted before insertion.
Returns `private' to indicate the drop was handled."
  (when-let ((path (and (string-prefix-p "file://" uri)
                        (dnd-get-local-file-name uri t))))
    (kuro--send-key (shell-quote-argument path))
    'private))

(defun kuro--setup-dnd ()
  "Configure drag-and-drop handling for the current Kuro buffer.
Adds kuro-specific handlers to `dnd-protocol-alist' buffer-locally."
  (setq-local dnd-protocol-alist
              (append '(("^file:///" . kuro-dnd-handle-uri)
                        ("^file://"  . kuro-dnd-handle-uri))
                      dnd-protocol-alist)))

(defun kuro--teardown-dnd ()
  "Remove Kuro drag-and-drop handlers from `dnd-protocol-alist'."
  (kill-local-variable 'dnd-protocol-alist))

(provide 'kuro-dnd)
;;; kuro-dnd.el ends here
