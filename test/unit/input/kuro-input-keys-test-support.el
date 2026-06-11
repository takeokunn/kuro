;;; kuro-input-keys-test-support.el --- Shared helpers  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input-keys)


(require 'ert)
(require 'cl-lib)

;; Capture sent keys
(defvar kuro-input-keys-test--sent nil
  "List of strings sent via `kuro--send-key' during tests (most recent first).")

(require 'kuro-input-keys)

;; Helper macro: run BODY with kuro--send-key captured to kuro-input-keys-test--sent.
;; Using cl-letf inside each test ensures isolation even when the real functions
;; are already bound (kuro.el was loaded as part of test-suite bootstrap).
(defmacro kuro-input-keys-test--with-capture (&rest body)
  "Execute BODY with `kuro--send-key' capturing to `kuro-input-keys-test--sent'."
  `(cl-letf (((symbol-function 'kuro--send-key)
              (lambda (data) (push data kuro-input-keys-test--sent)))
             ((symbol-function 'kuro--schedule-immediate-render)
              (lambda () nil)))
     (setq kuro-input-keys-test--sent nil)
     ,@body))



(provide 'kuro-input-keys-test-support)
;;; kuro-input-keys-test-support.el ends here
