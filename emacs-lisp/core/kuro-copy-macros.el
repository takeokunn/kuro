;;; kuro-copy-macros.el --- Macro helpers for Kuro copy mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <takeokunn@users.noreply.github.com>

;;; Commentary:

;; Macro-only helpers for `kuro-copy.el'.  Keeping these definitions in a
;; sibling file makes the runtime module smaller and keeps the generated
;; commands/data shape separate from the implementation.

;;; Code:

(defmacro kuro--def-copy-window-move (name arg docstring)
  "Define NAME as a copy-mode command for window-relative movement.
DOCSTRING becomes the generated command docstring.
ARG is passed directly to `move-to-window-line'."
  `(defun ,name () ,docstring (interactive) (move-to-window-line ,arg)))

(defmacro kuro--def-copy-search (name search-fn fallback-fn wrap-pos docstring)
  "Define NAME as a copy-mode command that repeats the last isearch pattern.
DOCSTRING becomes the generated command docstring.
SEARCH-FN is `search-forward' or `search-backward'.
FALLBACK-FN is called interactively when no prior pattern exists.
WRAP-POS is `(point-min)' or `(point-max)' for wrap-around."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let ((s (and (boundp 'isearch-string)
                   (not (string-empty-p isearch-string))
                   isearch-string)))
       (if (not s)
           (call-interactively #',fallback-fn)
         (unless (,search-fn s nil t)
           (goto-char ,wrap-pos)
           (unless (,search-fn s nil t)
             (message "Search failed: %s" s)))))))

(defmacro kuro--def-copy-goto-prompt (name direction fallback docstring)
  "Define NAME as a copy-mode prompt navigation command.
DOCSTRING becomes the generated command docstring.
NAME jumps to the nearest OSC 133 prompt in DIRECTION (:fwd or :bwd),
falling back to FALLBACK when no overlay marks exist."
  `(defun ,name ()
     ,docstring
     (interactive)
     (if-let* ((target (kuro--copy-find-prompt ,direction)))
         (goto-char target)
       (,fallback))))

(defmacro kuro--define-copy-mode-bindings (map bindings)
  "Install BINDINGS into MAP.
Each BINDINGS entry is (KEY . COMMAND).  KEY may be a vector or a
string accepted by `kbd'."
  `(dolist (binding ,bindings)
     (pcase-let ((`(,key . ,command) binding))
       (define-key ,map
                   (if (vectorp key) key (kbd key))
                   command))))

(defmacro kuro--def-copy-search-enter (name search-fn docstring)
  "Define NAME as a command that enters copy mode before SEARCH-FN.
DOCSTRING becomes the generated command docstring."
  `(defun ,name ()
     ,docstring
     (interactive)
     (kuro--with-kuro-mode
      (unless kuro--copy-mode
        (kuro--enter-copy-mode))
      (,search-fn))))

(provide 'kuro-copy-macros)

;;; kuro-copy-macros.el ends here
