;;; kuro-input-paste-test-support.el --- Shared paste test entrypoint  -*- lexical-binding: t; -*-

;;; Code:

;; kuro-input-paste requires kuro-ffi at load time.  Stub the symbols it uses so
;; the file loads in a batch/test environment without the dynamic module.
(unless (fboundp 'kuro--send-paste)
  (defalias 'kuro--send-paste (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))

(require 'kuro-input-paste)
(require 'kuro-input-paste-test-cases)
(require 'kuro-input-paste-test-macros)

(provide 'kuro-input-paste-test-support)
;;; kuro-input-paste-test-support.el ends here
