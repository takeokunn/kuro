;;; kuro-input-mode-macros.el --- Inline forms shared by kuro-input-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Shared `defsubst' and `defmacro' forms used by both `kuro-input-mode'
;; and `kuro-input-mode-ext'.  This file stays focused on CPS-style inline
;; forms and command-definition macros; buffer mutation helpers live in
;; `kuro-input-mode-buffer-macros'.
;;
;; Do not load this file directly; it is `require'd automatically by
;; `kuro-input-mode'.

;;; Code:

;; Forward declarations for helper continuations and shared state provided
;; by `kuro-input-mode-buffer-macros` and `kuro-input-mode-line-state`.

;; Declare the display-refresh continuation so defmacro expansions that
;; call it do not produce "undefined function" warnings at compile time.
(declare-function kuro--line-mode-update-display "kuro-input-mode-line-display" ())

(require 'kuro-input-mode-buffer-macros)
(require 'kuro-input-mode-line-state)


;;;; Line mode: CPS display continuation

(defmacro kuro--with-line-edit (&rest body)
  "Execute BODY mutating line state, then refresh the overlay display.
Encodes the invariant: every edit ends with a display update (CPS continuation)."
  `(progn ,@body (kuro--line-mode-update-display)))

(defmacro kuro--with-line-edit-undo (&rest body)
  "Push undo state, execute BODY mutating line state, then refresh display."
  `(progn (kuro--line-undo-push) ,@body (kuro--line-mode-update-display)))

(defmacro kuro--def-line-command (name docstring &rest body)
  "Define NAME as a line-mode command with BODY.
DOCSTRING becomes the generated command docstring.  Use this for
commands whose control flow does not fit the specialized navigation or
word-transform macros."
  (declare (indent 1))
  `(defun ,name ()
     ,docstring
     (interactive)
     ,@body))

(defmacro kuro--def-line-nav (name docstring &rest body)
  "Define NAME as a line-mode cursor-movement command.
DOCSTRING becomes the generated command docstring.
BODY runs unconditionally; `kuro--line-mode-update-display' is the
CPS continuation."
  (declare (indent 1))
  `(kuro--def-line-command ,name ,docstring
     ,@body
     (kuro--line-mode-update-display)))

(defmacro kuro--def-line-history-nav (name docstring guard stashp index-form buffer-form)
  "Define NAME using DOCSTRING as a line-mode history navigation command.
GUARD decides whether the command changes history state.  When STASHP is
non-nil, the current in-progress buffer is stashed before moving INDEX-FORM to
the new position and BUFFER-FORM into the line buffer."
  (declare (indent 1))
  `(kuro--def-line-command ,name ,docstring
     (when ,guard
       ,@(when stashp '((kuro--line-history-stash-if-fresh)))
       (setq kuro--line-history-idx ,index-form)
       (kuro--line-set-buffer ,buffer-form))))


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

(defsubst kuro--line-skip-unix-word-bwd (s p)
  "Retreat P to the start of the previous bash-style token in S.
Whitespace delimiters are space and tab only; punctuation stays inside the
token, matching `bash' `unix-word-rubout' behavior."
  (while (and (> p 0) (memq (aref s (1- p)) '(?\s ?\t)))
    (setq p (1- p)))
  (while (and (> p 0) (not (memq (aref s (1- p)) '(?\s ?\t))))
    (setq p (1- p)))
  p)

(defmacro kuro--line-apply-word-transform (replacement-form)
  "Apply REPLACEMENT-FORM to the next word and splice it back."
  (declare (indent 0))
  `(let* ((bounds (kuro--line-word-bounds-forward))
          (start  (car bounds))
          (end    (cdr bounds))
          (s      kuro--line-buffer))
     (when (> end start)
       (kuro--line-splice-with-undo start end ,replacement-form end))))

(defmacro kuro--def-line-word-transform (name docstring replacement-form)
  "Define NAME as a line-mode command that rewrites the next word.
DOCSTRING becomes the generated command docstring.  REPLACEMENT-FORM is
evaluated inside `kuro--line-apply-word-transform'."
  (declare (indent 2))
  `(kuro--def-line-command ,name ,docstring
     (kuro--line-apply-word-transform ,replacement-form)))

(provide 'kuro-input-mode-macros)

;;; kuro-input-mode-macros.el ends here
