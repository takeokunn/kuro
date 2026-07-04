;;; kuro-dnd.el --- Drag-and-drop support for Kuro terminal buffers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:
;; Handles drag-and-drop events in Kuro terminal buffers.
;; Dropping a local file inserts its shell-quoted path via the paste-safe
;; text path.

;;; Code:

(require 'cl-lib)
(require 'dnd)

(declare-function kuro--send-paste-or-raw "kuro-input-paste" (text))

(defconst kuro-dnd--file-uri-prefix "file://"
  "URI prefix accepted by Kuro drag-and-drop handling.")

(defun kuro-dnd--path-has-control-character-p (path)
  "Return non-nil when PATH has a terminal-control character."
  (cl-position-if (lambda (char) (or (< char 32) (= char 127))) path))

(defun kuro-dnd--file-uri-p (uri)
  "Return non-nil when URI is a file:// URI acceptable for DnD parsing."
  (and (stringp uri)
       (string-prefix-p kuro-dnd--file-uri-prefix uri)
       (not (kuro-dnd--path-has-control-character-p uri))))

(defun kuro-dnd--local-file-path-p (path)
  "Return non-nil when PATH is a safe local absolute path for DnD insertion."
  (and (stringp path)
       (< 0 (length path))
       (file-name-absolute-p path)
       (not (file-remote-p path))
       (file-exists-p path)
       (not (kuro-dnd--path-has-control-character-p path))))

(defun kuro-dnd--quoted-local-file-path (uri)
  "Return a shell-quoted local file path for file URI, or nil."
  (when (kuro-dnd--file-uri-p uri)
    (let ((path (ignore-errors (dnd-get-local-file-name uri t))))
      (when (kuro-dnd--local-file-path-p path)
        (shell-quote-argument path)))))

(defun kuro-dnd-handle-uri (uri _action)
  "Handle a drag-and-drop URI by inserting a safe local file path.
URI is a file:// URL.  The local path is shell-quoted before insertion.
Returns `private' to indicate the drop was handled."
  (when-let* ((text (kuro-dnd--quoted-local-file-path uri)))
    (kuro--send-paste-or-raw text)
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
