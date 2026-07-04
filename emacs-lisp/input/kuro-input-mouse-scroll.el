;;; kuro-input-mouse-scroll.el --- Mouse scrollback commands for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Scrollback commands for mouse wheel events live here.
;; `kuro-input-mouse.el' keeps mouse tracking state and encoding, while this
;; module owns the wheel-up / wheel-down fallback path that scrolls the buffer
;; when mouse tracking is off.

;;; Code:

(require 'kuro-input-mouse)
(require 'kuro-input-mouse-macros)

(declare-function kuro--scroll-up "kuro-ffi" (lines))
(declare-function kuro--scroll-down "kuro-ffi" (lines))
(declare-function kuro--get-scroll-offset "kuro-ffi" ())
(declare-function kuro--render-cycle "kuro-render-buffer" ())
(declare-function kuro--update-scroll-indicator "kuro-render-buffer" ())

(defvar kuro--initialized)
(defvar kuro--scroll-offset)
;; Forward references: `kuro--scroll-offset' is owned by kuro-input-send.el.

(defconst kuro--mouse-scroll-lines 5
  "Number of lines to scroll per mouse wheel event when mouse tracking is off.")

(kuro--def-scroll-command kuro--mouse-scroll-up--scrollback
  "Scroll terminal scrollback up by `kuro--mouse-scroll-lines' lines."
  (kuro--scroll-up kuro--mouse-scroll-lines)
  (max 0 (or (kuro--get-scroll-offset) (+ kuro--scroll-offset kuro--mouse-scroll-lines))))

(defun kuro--mouse-scroll-up ()
  "Handle wheel-up mouse scroll event.
When mouse tracking is active, forward to PTY as button 64.
Otherwise, scroll the terminal scrollback up by `kuro--mouse-scroll-lines'."
  (interactive)
  (if (> kuro--mouse-mode 0)
      (let ((btn 64))
        (kuro--dispatch-mouse-event btn t))
    (kuro--mouse-scroll-up--scrollback)))

(kuro--def-scroll-command kuro--mouse-scroll-down--scrollback
  "Scroll terminal scrollback down by `kuro--mouse-scroll-lines' lines."
  (kuro--scroll-down kuro--mouse-scroll-lines)
  (max 0 (or (kuro--get-scroll-offset) (- kuro--scroll-offset kuro--mouse-scroll-lines))))

(defun kuro--mouse-scroll-down ()
  "Handle wheel-down mouse scroll event.
When mouse tracking is active, forward to PTY as button 65.
Otherwise, scroll the terminal scrollback down by `kuro--mouse-scroll-lines'."
  (interactive)
  (if (> kuro--mouse-mode 0)
      (let ((btn 65))
        (kuro--dispatch-mouse-event btn t))
    (kuro--mouse-scroll-down--scrollback)))

(provide 'kuro-input-mouse-scroll)

;;; kuro-input-mouse-scroll.el ends here
