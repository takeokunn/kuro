;;; kuro-input-keymap-navigation-macros.el --- Macros for kuro-input-keymap-navigation.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Shifted-key macro extracted from kuro-input-keymap-navigation.el.

;;; Code:

(require 'kuro-input-macros)
(require 'kuro-input-keymap-data)

(defmacro kuro--modifier-arrow-send-and-render (xterm-seq)
  "Send XTERM-SEQ and schedule an immediate render."
  `(progn
     (kuro--send-key ,xterm-seq)
     (kuro--schedule-immediate-render)))

(defmacro kuro--define-modifier-arrow-bindings (map modifiers arrows)
  "Expand MODIFIERS x ARROWS into direct `define-key' forms on MAP.
Both table arguments may be literal lists or names of `defconst' tables.
Each generated binding installs the same send-and-render command that
dispatches xterm CSI sequences, while preserving the KKP all-escape fallback
when the arrow direction has a Unicode codepoint mapping."
  (let* ((modifier-list (cond
                         ((symbolp modifiers) (symbol-value modifiers))
                         ((and (consp modifiers) (eq (car modifiers) 'quote))
                          (cadr modifiers))
                         (t modifiers)))
         (arrow-list (cond
                      ((symbolp arrows) (symbol-value arrows))
                      ((and (consp arrows) (eq (car arrows) 'quote))
                       (cadr arrows))
                      (t arrows))))
    `(progn
       ,@(mapcan
          (lambda (modifier)
            (let ((mod-sym (car modifier))
                  (xterm-mod (cdr modifier)))
              (mapcar
               (lambda (arrow)
                 (let* ((dir (car arrow))
                        (final-byte (cdr arrow))
                        (event (intern (format "%s-%s" mod-sym dir)))
                        (xterm-seq (format "\e[1;%d%c" xterm-mod final-byte))
                        (kkp-mod (1+ xterm-mod))
                        (kkp-cp (cdr (assq dir kuro--kkp-arrow-codepoints))))
                   `(define-key
                     ,map
                     (vector ',event)
                     (lambda ()
                       (interactive)
                       ,(if kkp-cp
                            `(kuro--with-kkp-all-escape
                                 ,(format "\e[%d;%du" kkp-cp kkp-mod)
                               (kuro--modifier-arrow-send-and-render ,xterm-seq))
                          `(kuro--modifier-arrow-send-and-render ,xterm-seq))))))
               arrow-list)))
          modifier-list))))

(defmacro kuro--def-shifted-key (name kkp-seq legacy-seq docstring)
  "Define NAME as an interactive key-sender dispatching on KKP state.
DOCSTRING becomes the generated command docstring.
Sends KKP-SEQ when the flag is active, or LEGACY-SEQ otherwise.
Then schedule a render."
  `(defun ,name ()
     ,docstring
     (interactive)
     (kuro--with-kkp-disambiguate
         (kuro--send-key ,kkp-seq)
       (kuro--send-key ,legacy-seq))
     (kuro--schedule-immediate-render)))

(provide 'kuro-input-keymap-navigation-macros)

;;; kuro-input-keymap-navigation-macros.el ends here
