;;; kuro-input-test-support.el --- Shared helpers for kuro-input unit tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared test support for kuro-input.el unit tests.
;; This file centralises setup and shared macros for the split test files:
;;   kuro-input-test.el, kuro-input-test-2.el, kuro-input-test-3.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input)

;; Ensure kuro--keymap is populated before keymap-lookup tests run.
(when (fboundp 'kuro--build-keymap)
  (kuro--build-keymap))

(defmacro kuro-input-test--capture-sent (&rest body)
  "Execute BODY with kuro--send-key stubbed; return list of sent strings."
  `(let ((sent nil)
         (kuro--initialized t))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (push s sent))))
       ,@body)
     (nreverse sent)))

(defmacro kuro-input-test--assert-sends (call expected)
  "Assert that CALL sends EXPECTED sequence(s)."
  `(should (equal (kuro-input-test--capture-sent ,call) ,expected)))

(defmacro kuro-input-test--assert-sends-in-mode (mode call expected)
  "Assert CALL sends EXPECTED with `kuro--application-cursor-keys-mode' bound to MODE."
  `(let ((kuro--application-cursor-keys-mode ,mode))
     (should (equal (kuro-input-test--capture-sent ,call) ,expected))))

(defmacro kuro-input-test--assert-sends-in-buffer-mode (mode call expected)
  "Assert CALL sends EXPECTED in a temp buffer where cursor-keys mode is MODE."
  `(with-temp-buffer
     (setq-local kuro--application-cursor-keys-mode ,mode)
     (should (equal (kuro-input-test--capture-sent ,call) ,expected))))

(defmacro kuro-input-test--assert-self-insert-sends (char expected)
  "Assert `kuro--self-insert' sends EXPECTED when `last-command-event' is CHAR."
  `(let ((last-command-event ,char))
     (should (equal (kuro-input-test--capture-sent (kuro--self-insert)) ,expected))))

(defmacro kuro-input-test--with-scroll-stubs (scroll-up-fn scroll-down-fn
                                              get-offset-fn &rest body)
  "Run BODY with scroll FFI functions stubbed and kuro--initialized=t."
  (declare (indent 3))
  `(with-temp-buffer
     (setq-local kuro--initialized t
                 kuro--scroll-offset 0)
     (cl-letf (((symbol-function 'kuro--scroll-up)        ,scroll-up-fn)
               ((symbol-function 'kuro--scroll-down)      ,scroll-down-fn)
               ((symbol-function 'kuro--get-scroll-offset) ,get-offset-fn)
               ((symbol-function 'kuro--render-cycle)     #'ignore))
       ,@body)))

(provide 'kuro-input-test-support)
;;; kuro-input-test-support.el ends here
