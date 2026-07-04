;;; kuro-stream-test-macros.el --- Macros for kuro-stream tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared test-generation macros for kuro-stream-test.el.

;;; Code:

(require 'ert)
(require 'kuro-stream-test-cases)

(defmacro kuro-stream-test--def-min-interval-lazy-init (test-name frame-rate)
  `(ert-deftest ,test-name ()
     ,(format "kuro--stream-min-interval lazy init computes correct interval for %dfps." frame-rate)
     (kuro-stream-test--with-buffer
       (let ((kuro-frame-rate ,frame-rate))
         (setq kuro--stream-min-interval nil)
         (let ((result (or kuro--stream-min-interval
                           (setq kuro--stream-min-interval
                                 (/ 1.0 kuro-frame-rate)))))
           (should (floatp result))
           (should (< (abs (- result (/ 1.0 ,frame-rate))) 1e-10))
           (should (floatp kuro--stream-min-interval)))))))

(defmacro kuro-stream-test--def-stop-reset-sim (test-name var-sym expected)
  `(ert-deftest ,test-name ()
     ,(format "Simulated stop resets `%s' to %S." var-sym expected)
     (kuro-stream-test--with-buffer
       ,(cond ((null expected)    `(setq ,var-sym (/ 1.0 60)))
              ((zerop expected)   `(setq ,var-sym (float-time)))
              (t                  `(setq ,var-sym t)))
       (setq ,var-sym ,expected)
       ,(if (null expected)
            `(should (null ,var-sym))
          `(should (= ,var-sym ,expected))))))

(provide 'kuro-stream-test-macros)

;;; kuro-stream-test-macros.el ends here
