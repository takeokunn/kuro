;;; kuro-navigation-test-support.el --- Shared helpers for navigation tests  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--get-focus-events)
  (defalias 'kuro--get-focus-events (lambda () nil)))

(require 'kuro-navigation)

;;; Helpers

(defmacro kuro-nav-test--with-prompts (positions &rest body)
  "Run BODY in a temp buffer with `kuro--prompt-positions' set to POSITIONS.
The buffer starts with N+1 newlines so that line numbers map predictably:
line-number-at-pos at point-min returns 1, so cur-line = 0.
Each `forward-line N' places point at line N+1, cur-line = N."
  (declare (indent 1))
  `(with-temp-buffer
     ;; Insert enough lines so forward-line never goes out of range.
     (dotimes (_ 30) (insert "\n"))
     (goto-char (point-min))
     (setq-local kuro--prompt-positions ,positions)
     ,@body))

(provide 'kuro-navigation-test-support)
;;; kuro-navigation-test-support.el ends here
