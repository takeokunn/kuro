;;; kuro-input-paste-test-support.el --- Shared helpers  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

;; kuro-input-paste requires kuro-ffi at load time.  Stub the symbols it
;; uses so the file loads in a batch/test environment without the module.
(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))

(require 'kuro-input-paste)

(defmacro kuro-paste-test--capture-sent (&rest body)
  "Execute BODY with kuro--send-key and kuro--schedule-immediate-render stubbed.
Returns a list of strings passed to kuro--send-key, in call order."
  `(let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (push s sent)))
               ((symbol-function 'kuro--schedule-immediate-render)
                (lambda () nil)))
       ,@body)
     (nreverse sent)))

(defmacro kuro-paste-test--with-send-paste (bracketed-p text &rest body)
  "Test `kuro--send-paste-or-raw' with BRACKETED-P mode and TEXT.
BODY runs with `captured' bound to what `kuro--send-key' received."
  `(with-temp-buffer
     (let ((kuro--bracketed-paste-mode ,bracketed-p)
           (captured nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq captured s))))
         (kuro--send-paste-or-raw ,text)
         ,@body))))


(provide 'kuro-input-paste-test-support)
;;; kuro-input-paste-test-support.el ends here
