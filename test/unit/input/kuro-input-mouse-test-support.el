;;; kuro-input-mouse-test-support.el --- Shared helpers for mouse input tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Compatibility entrypoint for the split mouse input test helpers.

;;; Code:

(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))
(unless (fboundp 'kuro--mouse-mode-query)
  (defalias 'kuro--mouse-mode-query (lambda () 0)))
(unless (fboundp 'kuro--scroll-up)
  (defalias 'kuro--scroll-up (lambda (_n) nil)))
(unless (fboundp 'kuro--scroll-down)
  (defalias 'kuro--scroll-down (lambda (_n) nil)))
(unless (fboundp 'kuro--get-scroll-offset)
  (defalias 'kuro--get-scroll-offset (lambda () 0)))
(unless (fboundp 'kuro--render-cycle)
  (defalias 'kuro--render-cycle (lambda () nil)))
(unless (fboundp 'kuro--update-scroll-indicator)
  (defalias 'kuro--update-scroll-indicator (lambda () nil)))

(require 'cl-lib)
(require 'kuro-input-mouse)
(require 'kuro-input-mouse-scroll)
(require 'kuro-input-mouse-test-cases)
(require 'kuro-input-mouse-test-macros)

(provide 'kuro-input-mouse-test-support)

;;; kuro-input-mouse-test-support.el ends here
