;;; kuro-input-mode-macros.el --- Inline forms shared by kuro-input-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Shared `defsubst' and `defmacro' forms used by both `kuro-input-mode'
;; and `kuro-input-mode-ext'.  Extracted here so the byte-compiler sees all
;; inline definitions before it compiles either half.
;;
;; Do not load this file directly; it is `require'd automatically by
;; `kuro-input-mode'.

;;; Code:

;; Forward declarations — suppress free-variable warnings when the
;; defsubsts below are byte-compiled before kuro-input-mode.el loads.
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro--line-undo-stack)

;; Declare the display-refresh continuation so defmacro expansions that
;; call it do not produce "undefined function" warnings at compile time.
(declare-function kuro--line-mode-update-display "kuro-input-mode" ())

(defconst kuro--line-undo-max-depth 100
  "Maximum number of undo states retained in `kuro--line-undo-stack'.")


;;;; Line mode: undo stack (inline)

(defsubst kuro--line-undo-push ()
  "Push the current line-buffer state onto `kuro--line-undo-stack'.
Called at the start of every editing command that mutates `kuro--line-buffer'."
  (push (cons kuro--line-buffer kuro--line-point) kuro--line-undo-stack)
  (when (> (length kuro--line-undo-stack) kuro--line-undo-max-depth)
    (setq kuro--line-undo-stack
          (seq-take kuro--line-undo-stack kuro--line-undo-max-depth))))


;;;; Line mode: CPS display continuation

(defmacro kuro--with-line-edit (&rest body)
  "Execute BODY mutating line state, then refresh the overlay display.
Encodes the invariant: every edit ends with a display update (CPS continuation)."
  `(progn ,@body (kuro--line-mode-update-display)))

(defmacro kuro--with-line-edit-undo (&rest body)
  "Push undo state, execute BODY mutating line state, then refresh display."
  `(progn (kuro--line-undo-push) ,@body (kuro--line-mode-update-display)))

(defmacro kuro--def-line-nav (name docstring &rest body)
  "Define a line-mode cursor-movement command.
BODY runs unconditionally; `kuro--line-mode-update-display' is the
CPS continuation."
  `(defun ,name ()
     ,docstring
     (interactive)
     ,@body
     (kuro--line-mode-update-display)))


;;;; Line mode: word boundary primitives (inline)

(defsubst kuro--line-skip-non-word-fwd (s p)
  "Advance P past non-word characters in S (forward scan)."
  (let ((len (length s)))
    (while (and (< p len) (/= (char-syntax (aref s p)) ?w))
      (setq p (1+ p)))
    p))

(defsubst kuro--line-skip-word-fwd (s p)
  "Advance P past word characters in S (forward scan)."
  (let ((len (length s)))
    (while (and (< p len) (= (char-syntax (aref s p)) ?w))
      (setq p (1+ p)))
    p))

(defsubst kuro--line-skip-non-word-bwd (s p)
  "Retreat P past non-word characters in S (backward scan)."
  (while (and (> p 0) (/= (char-syntax (aref s (1- p))) ?w))
    (setq p (1- p)))
  p)

(defsubst kuro--line-skip-word-bwd (s p)
  "Retreat P past word characters in S (backward scan)."
  (while (and (> p 0) (= (char-syntax (aref s (1- p))) ?w))
    (setq p (1- p)))
  p)

(provide 'kuro-input-mode-macros)

;;; kuro-input-mode-macros.el ends here
