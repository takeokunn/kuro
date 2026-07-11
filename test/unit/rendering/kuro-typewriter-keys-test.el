;;; kuro-typewriter-keys-test.el --- Typewriter tests: key bytes, dead-buffer  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-typewriter.el — Groups 16-17.
;; Groups 10-15 are in kuro-typewriter-ext-test.el.
;; Helper macros are in kuro-typewriter-test-support.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-typewriter-test-support)

;;; Group 16 — special key byte sequences (RET, TAB, DEL, Ctrl codes)

(defconst kuro-typewriter-test--send-named-key-table
  '((kuro-typewriter-ret-sends-carriage-return kuro--RET "\r")
    (kuro-typewriter-tab-sends-horizontal-tab  kuro--TAB "\t")
    (kuro-typewriter-del-sends-rubout-byte     kuro--DEL "\x7f"))
  "Table of (test-name fn-sym expected-bytes) for named-key send functions.")

(defmacro kuro-typewriter-test--def-send-named-key (test-name fn-sym expected)
  `(ert-deftest ,test-name ()
     ,(format "`%s' sends %S to the PTY." fn-sym expected)
     (kuro-typewriter-test--with-key-capture sent
       (,fn-sym)
       (should (equal (car sent) ,expected)))))

(kuro-typewriter-test--def-send-named-key kuro-typewriter-ret-sends-carriage-return kuro--RET "\r")
(kuro-typewriter-test--def-send-named-key kuro-typewriter-tab-sends-horizontal-tab  kuro--TAB "\t")
(kuro-typewriter-test--def-send-named-key kuro-typewriter-del-sends-rubout-byte     kuro--DEL "\x7f")

(ert-deftest kuro-typewriter-test--all-named-keys-send-correct-bytes ()
  "Invariant: each named-key function sends exactly the expected single byte."
  (dolist (entry kuro-typewriter-test--send-named-key-table)
    (pcase-let ((`(,_name ,fn-sym ,expected) entry))
      (kuro-typewriter-test--with-key-capture sent
        (funcall fn-sym)
        (should (equal (car sent) expected))))))

(defmacro kuro-typewriter-test--def-send-special (test-name byte)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--send-special' %d sends (string %d) to the PTY." byte byte)
     (kuro-typewriter-test--with-key-capture sent
       (kuro--send-special ,byte)
       (should (equal (car sent) (string ,byte))))))

(kuro-typewriter-test--def-send-special kuro-typewriter-send-special-ctrl-a               1)
(kuro-typewriter-test--def-send-special kuro-typewriter-send-special-ctrl-c               3)
(kuro-typewriter-test--def-send-special kuro-typewriter-send-special-ctrl-z              26)
(kuro-typewriter-test--def-send-special kuro-typewriter-send-special-ctrl-bracket        27)
(kuro-typewriter-test--def-send-special kuro-typewriter-send-special-ctrl-backslash      28)
(kuro-typewriter-test--def-send-special kuro-typewriter-send-special-ctrl-right-bracket  29)

(ert-deftest kuro-typewriter-send-special-sends-exactly-one-byte-string ()
  "kuro--send-special always sends a single-byte string to the PTY."
  (dolist (byte '(1 3 9 13 26 27 28 29 127))
    (kuro-typewriter-test--with-key-capture sent
      (kuro--send-special byte)
      (should (= (length sent) 1))
      (should (= (length (car sent)) 1)))))

;;; Group 17 — kuro--typewriter-tick: dead buffer after enqueue

(defmacro kuro-typewriter-test--with-dead-buf-closure (captured-fn-sym &rest body)
  "Allocate a buffer with typewriter state, enqueue \"hello\", capture the timer closure, kill buffer, run BODY."
  (declare (indent 1))
  `(let ((,captured-fn-sym nil))
     (let ((buf (generate-new-buffer "*kuro-tw-dead-test*")))
       (unwind-protect
           (with-current-buffer buf
             (let ((kuro-typewriter-effect t)
                   (kuro-typewriter-chars-per-second 60)
                   (kuro--initialized t)
                   kuro--typewriter-queue kuro--typewriter-timer
                   kuro--typewriter-current-row kuro--typewriter-current-text
                   (kuro--typewriter-written-len 0))
               (kuro--typewriter-enqueue 0 "hello")
               (kuro-typewriter-test--with-timer-stub timer-args
                 (kuro--start-typewriter-timer)
                 (setq ,captured-fn-sym (nth 2 timer-args)))))
         (kill-buffer buf)))
     ,@body))

(ert-deftest kuro-typewriter-ext-tick-handles-dead-buffer-after-enqueue ()
  "The timer closure is a no-op and signals no error when the buffer is dead."
  (kuro-typewriter-test--with-dead-buf-closure captured-fn
    (should-not
     (condition-case err
         (progn (when captured-fn (funcall captured-fn)) nil)
       (error err)))))

(ert-deftest kuro-typewriter-ext-tick-dead-buffer-does-not-render ()
  "kuro--typewriter-tick is never called when the captured buffer is dead."
  (kuro-typewriter-test--with-dead-buf-closure captured-fn
    (let ((tick-called nil))
      (cl-letf (((symbol-function 'kuro--typewriter-tick)
                 (lambda () (setq tick-called t))))
        (when captured-fn (funcall captured-fn)))
      (should-not tick-called))))

(ert-deftest kuro-typewriter-ext-tick-state-cleared-after-dead-buffer ()
  "kuro--typewriter-tick resets state vars to nil/0 when queue is drained."
  (with-temp-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (kuro--initialized t)
          (kuro--typewriter-current-row 0)
          (kuro--typewriter-current-text "hi")
          (kuro--typewriter-written-len 2)   ; fully written
          (kuro--typewriter-queue nil))
      (kuro-typewriter-test--with-write-partial-log write-calls
        (kuro--typewriter-tick)
        (should (null write-calls))
        (kuro-typewriter-test--assert-state nil nil 0 nil)))))

(provide 'kuro-typewriter-keys-test)

;;; kuro-typewriter-keys-test.el ends here
