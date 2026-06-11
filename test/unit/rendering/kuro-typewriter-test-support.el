;;; kuro-typewriter-test-support.el --- Shared helpers for typewriter tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared test helpers for kuro-typewriter.el unit tests.
;; Required by both kuro-typewriter-test.el (Groups 1-9)
;; and kuro-typewriter-ext-test.el (Groups 10-17).

;;; Code:

(require 'cl-lib)
(require 'kuro-typewriter)

(defmacro kuro-typewriter-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with typewriter state initialized.
`kuro--initialized' is set to t so that `kuro--typewriter-tick' guards pass."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized t)
           kuro--typewriter-queue
           kuro--typewriter-timer
           kuro--typewriter-current-row
           kuro--typewriter-current-text
           (kuro--typewriter-written-len 0)
           (kuro--typewriter-current-text-len 0))
       ,@body)))

(defmacro kuro-typewriter-test--with-timer-stub (var &rest body)
  "Run BODY with `run-with-timer' stubbed; VAR captures the created timer.
The stub stores (DELAY FN) as a list in VAR and returns the symbol `fake-timer'."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'run-with-timer)
                (lambda (delay _repeat fn)
                  (setq ,var (list delay fn))
                  'fake-timer)))
       ,@body)))

(defmacro kuro-typewriter-test--with-key-capture (var &rest body)
  "Run BODY with `kuro--send-key' captured into VAR (most recent first).
`kuro--schedule-immediate-render' is stubbed as a no-op."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (push data ,var)))
               ((symbol-function 'kuro--schedule-immediate-render)
                (lambda () nil)))
       ,@body)))

(provide 'kuro-typewriter-test-support)

;;; kuro-typewriter-test-support.el ends here
