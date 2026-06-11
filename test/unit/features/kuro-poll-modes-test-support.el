;;; kuro-poll-modes-test-support.el --- Shared helpers for kuro-poll-modes-test  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-poll-modes)


(require 'ert)
(require 'cl-lib)
(require 'kuro-poll-modes)

;;; Test helpers

(defmacro kuro-poll-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with poll-modes state initialized."
  `(with-temp-buffer
     (let ((kuro--initialized t)
           (kuro--mode-poll-frame-count 0)
           (kuro--prompt-positions nil)
           (kuro--application-cursor-keys-mode nil)
           (kuro--app-keypad-mode nil)
           (kuro--mouse-mode nil)
           (kuro--mouse-sgr nil)
           (kuro--mouse-pixel-mode nil)
           (kuro--bracketed-paste-mode nil)
           (kuro--keyboard-flags 0)
           (kuro-kill-buffer-on-exit nil))
       ,@body)))


(provide 'kuro-poll-modes-test-support)
;;; kuro-poll-modes-test-support.el ends here
