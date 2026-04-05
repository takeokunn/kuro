;;; kuro-stream-test-support.el --- Shared helpers for kuro-stream tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared test support for kuro-stream unit tests.
;; This file centralizes stream-state setup, FFI stubs, and the common
;; temp-buffer macros used across the split stream test files.

;;; Code:

(require 'cl-lib)

(defvar-local kuro--stream-idle-timer nil)
(defvar-local kuro--stream-last-render-time 0.0)
(defvar-local kuro--stream-min-interval nil)

(defmacro kuro-stream-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with stream state reset to initial values."
  `(with-temp-buffer
     (setq kuro--stream-idle-timer nil
           kuro--stream-last-render-time 0.0
           kuro--stream-min-interval nil)
     ,@body))

(cl-defmacro kuro-stream-test--with-state ((&key (initialized t) timer interval) &rest body)
  "Run BODY in a temp buffer with stream state variables bound."
  (declare (indent 1))
  `(with-temp-buffer
     (setq-local kuro--initialized ,initialized
                 kuro--stream-idle-timer ,timer
                 kuro--stream-last-render-time 0.0
                 kuro--stream-min-interval ,interval)
     ,@body))

(defmacro kuro-stream-test--idle-tick-with-buffer (&rest body)
  "Run BODY in a fresh temp buffer with streaming state initialized."
  `(with-temp-buffer
     (setq-local kuro--initialized nil
                 kuro--stream-idle-timer nil
                 kuro--stream-last-render-time 0.0
                 kuro--stream-min-interval nil)
     ,@body))

(dolist (binding '((kuro-core-init . (lambda (&rest _) t))
                   (kuro-core-resize . (lambda (&rest _) t))
                   (kuro-core-send-key . (lambda (&rest _) nil))
                   (kuro-core-poll-updates . (lambda () nil))
                   (kuro-core-poll-updates-with-faces . (lambda () nil))
                   (kuro-core-get-cursor . (lambda () nil))
                   (kuro-core-is-cursor-visible . (lambda () t))
                   (kuro-core-get-cursor-shape . (lambda () 0))
                   (kuro-core-get-mouse-tracking-mode . (lambda () nil))
                   (kuro-core-get-bracketed-paste . (lambda () nil))
                   (kuro-core-is-alt-screen-active . (lambda () nil))
                   (kuro-core-get-focus-tracking . (lambda () nil))
                   (kuro-core-get-kitty-kb-flags . (lambda () 0))
                   (kuro-core-get-sync-update-active . (lambda () nil))
                   (kuro-core-shutdown . (lambda () nil))
                   (kuro-core-has-pending-output . (lambda () nil))
                   (kuro-core-get-and-clear-title . (lambda () nil))
                   (kuro-core-get-cwd . (lambda () nil))
                   (kuro-core-poll-clipboard-actions . (lambda () nil))
                   (kuro-core-poll-prompt-marks . (lambda () nil))
                   (kuro-core-get-image . (lambda (_id) nil))
                   (kuro-core-poll-image-notifications . (lambda () nil))
                   (kuro-core-consume-scroll-events . (lambda () nil))
                   (kuro-core-get-palette-updates . (lambda () nil))
                   (kuro-core-get-default-colors . (lambda () nil))
                   (kuro-core-get-scrollback . (lambda (_n) nil))
                   (kuro-core-clear-scrollback . (lambda () nil))
                   (kuro-core-set-scrollback-max-lines . (lambda (_n) nil))
                   (kuro-core-get-scrollback-count . (lambda () 0))
                   (kuro-core-scroll-up . (lambda (_n) nil))
                   (kuro-core-scroll-down . (lambda (_n) nil))
                   (kuro-core-get-scroll-offset . (lambda () 0))
                   (kuro--typewriter-enqueue . (lambda (&rest _) nil))
                   (kuro--start-typewriter-timer . (lambda () nil))
                   (kuro--stop-typewriter-timer . (lambda () nil))))
  (pcase-let ((`(,sym . ,fn) binding))
    (unless (fboundp sym)
      (fset sym fn))))

(require 'kuro-stream)

(provide 'kuro-stream-test-support)

;;; kuro-stream-test-support.el ends here
