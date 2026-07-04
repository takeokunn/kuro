;;; kuro-input-test-macros.el --- Shared macros for kuro-input unit tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared macro layer for kuro-input.el unit tests.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input)
(require 'kuro-input-test-cases)

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
               ((symbol-function 'kuro--render-cycle)     #'ignore)
               ((symbol-function 'kuro--update-scroll-indicator) #'ignore))
       ,@body)))

(defmacro kuro-input-test--def-named-key-sequence-case (case)
  "Define one named-key sequence lookup test from CASE."
  (pcase-let ((`(,test-name ,key ,expected) case))
    `(ert-deftest ,test-name ()
       (should (equal (cdr (assq ',key kuro--named-key-sequences))
                      ,expected)))))

(defmacro kuro-input-test--deftest-named-key-sequence-cases ()
  "Define all named-key sequence lookup tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-input-test--def-named-key-sequence-case ,case))
               kuro-input-test--named-key-sequence-cases)))

(defmacro kuro-input-test--def-encode-key-event-case (case)
  "Define one `kuro--encode-key-event' test from CASE."
  (pcase-let ((`(,test-name ,event ,modifiers ,basic-type ,expected) case))
    `(ert-deftest ,test-name ()
       (cl-letf (((symbol-function 'event-modifiers)
                  (lambda (_ev) ',modifiers))
                 ((symbol-function 'event-basic-type)
                  (lambda (_ev) ',basic-type)))
         ,(if expected
              `(should (equal (kuro--encode-key-event ',event) ,expected))
            `(should-not (kuro--encode-key-event ',event)))))))

(defmacro kuro-input-test--deftest-encode-key-event-cases ()
  "Define all `kuro--encode-key-event' tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-input-test--def-encode-key-event-case ,case))
               kuro-input-test--encode-key-event-cases)))

(provide 'kuro-input-test-macros)
;;; kuro-input-test-macros.el ends here
