;;; kuro-input-send-scroll.el --- Scroll-aware send helpers for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Scroll-aware send commands and scrollback navigation live here so the
;; core sender file stays focused on byte emission and shared keyboard state.

;;; Code:

(require 'kuro-input-macros)
(require 'kuro-input-send)

;; Forward references from kuro-input-send.el.
(declare-function kuro--send-ctrl "kuro-input-send" (byte))
(declare-function kuro--send-meta "kuro-input-send" (char))
;; Scroll helpers come from the FFI layer.
(declare-function kuro--scroll-up "kuro-ffi-osc" (n))
(declare-function kuro--scroll-down "kuro-ffi-osc" (n))
(declare-function kuro--get-scroll-offset "kuro-ffi-osc" ())
;; Render hooks are called by the shared scroll-command macro.
(declare-function kuro--render-cycle "kuro-input-render" ())
(declare-function kuro--update-scroll-indicator "kuro-render-buffer" ())

(defconst kuro--scroll-to-bottom-sentinel 999999
  "Sentinel value for `kuro-scroll-to-bottom': scrolls past any real content.")

(defun kuro--scroll-aware-ctrl-v ()
  "Send the Control-V byte to PTY when at live view; scroll down in scrollback.
When `kuro--scroll-offset' > 0 the user is browsing scrollback history,
so this acts like `kuro-scroll-down' (toward live output) matching the
standard Emacs `scroll-up-command' semantics.  At live view (offset 0),
the raw control byte 22 is sent to the PTY."
  (interactive)
  (if (> kuro--scroll-offset 0)
      (kuro-scroll-down)
    (kuro--send-ctrl 22)))

(defun kuro--scroll-aware-meta-v ()
  "Send Meta-v to PTY when at live view; scroll up when in scrollback.
When `kuro--scroll-offset' > 0, this acts like `kuro-scroll-up' (toward
history) matching the standard Emacs `scroll-down-command' semantics.
At live view (offset 0), ESC + v is sent to the PTY."
  (interactive)
  (if (> kuro--scroll-offset 0)
      (kuro-scroll-up)
    (kuro--send-meta ?v)))

;;;###autoload
(kuro--def-scroll-command kuro-scroll-up
  "Scroll back into terminal history by one screenful."
  (let ((lines (window-body-height)))
    (kuro--scroll-up lines))
  (let ((lines (window-body-height)))
    (or (kuro--get-scroll-offset) (+ kuro--scroll-offset lines))))

;;;###autoload
(kuro--def-scroll-command kuro-scroll-down
  "Scroll toward live terminal output by one screenful."
  (let ((lines (window-body-height)))
    (kuro--scroll-down lines))
  (let ((lines (window-body-height)))
    (or (kuro--get-scroll-offset) (max 0 (- kuro--scroll-offset lines)))))

;;;###autoload
(kuro--def-scroll-command kuro-scroll-bottom
  "Return immediately to live terminal output."
  (kuro--scroll-down kuro--scroll-to-bottom-sentinel)
  (or (kuro--get-scroll-offset) 0))

(provide 'kuro-input-send-scroll)

;;; kuro-input-send-scroll.el ends here
