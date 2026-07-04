;;; kuro-input-mouse-macros.el --- Mouse command macros for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Macro helpers for mouse command generation in `kuro-input-mouse.el'.
;; Keeping them in a sibling file makes byte-compile load order explicit while
;; leaving the runtime implementation in the main mouse module.

;;; Code:

(defmacro kuro--dispatch-mouse-event (btn press)
  "When mouse tracking is active and BTN is non-nil, encode and forward it.
BTN is an integer button index (0/1/2/64/65) or nil to skip.
PRESS is non-nil for press, nil for release.
Routes through `kuro--encode-mouse-sgr' or `kuro--encode-mouse' based on mode."
  `(when (and (> kuro--mouse-mode 0) ,btn)
     (let ((seq (if kuro--mouse-sgr
                    (kuro--encode-mouse-sgr last-input-event ,btn ,press)
                  (kuro--encode-mouse last-input-event ,btn ,press))))
       (when seq (kuro--send-key seq)))))

(defconst kuro--mouse-button-alist
  '((mouse-1 . 0) (mouse-2 . 1) (mouse-3 . 2))
  "Alist mapping mouse button `event-basic-type' symbols to PTY indices.")

(defmacro kuro--def-mouse-cmd (name btn-form press doc)
  "Define interactive mouse command NAME dispatching BTN-FORM / PRESS to PTY.
BTN-FORM is evaluated at call time: a literal integer for scroll commands, or an
`alist-get' expression over `event-basic-type' for button commands.
PRESS is t for press events, nil for release.
DOC is the docstring for the generated command."
  `(defun ,name ()
     ,doc
     (interactive)
     (let ((btn ,btn-form))
       (kuro--dispatch-mouse-event btn ,press))))

(defmacro kuro--def-scroll-command (name doc scroll-form offset-form)
  "Define interactive scroll command NAME with docstring DOC.
SCROLL-FORM is the FFI call (e.g. `(kuro--scroll-up lines)').
OFFSET-FORM is the expression assigned to `kuro--scroll-offset' after the
call.  The generated function is guarded by `kuro--initialized', calls
`kuro--render-cycle', and calls `kuro--update-scroll-indicator'."
  (declare (indent 1))
  `(defun ,name ()
     ,doc
     (interactive)
     (when kuro--initialized
       ,scroll-form
       (setq kuro--scroll-offset ,offset-form)
       (kuro--render-cycle)
       (kuro--update-scroll-indicator))))

(provide 'kuro-input-mouse-macros)

;;; kuro-input-mouse-macros.el ends here
