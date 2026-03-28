;;; kuro-ffi-test.el --- Unit tests for kuro-ffi.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-ffi.el (kuro--call macro, FFI wrapper behaviour).
;; These tests exercise only pure Emacs Lisp logic without the Rust module.
;; All Rust FFI functions are stubbed with cl-letf.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-ffi)

;;; Test helpers

(defmacro kuro-ffi-test--with-stub (fn lambda-body &rest body)
  "Execute BODY with `kuro--initialized' t, `kuro--session-id' 1, and FN stubbed.
FN is a symbol; LAMBDA-BODY is the stub lambda expression (unquoted).
Reduces the repeated `(let ((kuro--initialized t)) (cl-letf ...))' boilerplate."
  `(let ((kuro--initialized t)
         (kuro--session-id 1))
     (cl-letf (((symbol-function ',fn) ,lambda-body))
       ,@body)))

;;; Group 1: kuro--call macro

(ert-deftest kuro-ffi-call-returns-nil-when-not-initialized ()
  "kuro--call returns nil (fallback) when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--call nil t))))

(ert-deftest kuro-ffi-call-returns-nil-not-fallback-when-not-initialized ()
  "kuro--call returns nil (not fallback) when not initialized: fallback is only for errors."
  ;; kuro--call expands to (when kuro--initialized ...).
  ;; When not initialized, `when' returns nil regardless of fallback value.
  (let ((kuro--initialized nil))
    (should-not (kuro--call 42 t))))

(ert-deftest kuro-ffi-call-executes-body-when-initialized ()
  "kuro--call evaluates BODY and returns its value when initialized."
  (let ((kuro--initialized t))
    (should (= 99 (kuro--call 0 99)))))

(ert-deftest kuro-ffi-call-returns-fallback-on-error ()
  "kuro--call catches errors in BODY and returns fallback."
  (let ((kuro--initialized t))
    (should (= -1 (kuro--call -1 (error "boom"))))))

(ert-deftest kuro-ffi-call-fallback-nil-on-error ()
  "kuro--call with nil fallback returns nil on error."
  (let ((kuro--initialized t))
    (should-not (kuro--call nil (error "boom")))))

(ert-deftest kuro-ffi-call-evaluates-multiple-body-forms ()
  "kuro--call evaluates multiple body forms and returns the last value."
  (let ((kuro--initialized t)
        (side-effect nil))
    (let ((result (kuro--call nil
                    (setq side-effect t)
                    :last-value)))
      (should (eq result :last-value))
      (should side-effect))))

;;; Group 2: kuro--init

(ert-deftest kuro-ffi-init-sets-initialized-on-success ()
  "kuro--init sets kuro--initialized to t when kuro-core-init returns non-nil."
  (let ((kuro--initialized nil))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _rows _cols) t)))
      (kuro--init "bash")
      (should kuro--initialized))))

(ert-deftest kuro-ffi-init-leaves-uninitialized-on-nil-result ()
  "kuro--init leaves kuro--initialized nil when kuro-core-init returns nil."
  (let ((kuro--initialized nil))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _rows _cols) nil)))
      (kuro--init "bash")
      (should-not kuro--initialized))))

(ert-deftest kuro-ffi-init-returns-nil-on-error ()
  "kuro--init returns nil and does not raise when kuro-core-init errors."
  (let ((kuro--initialized nil))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _rows _cols) (error "no PTY"))))
      (let ((result (kuro--init "bash")))
        (should-not result)
        (should-not kuro--initialized)))))

(ert-deftest kuro-ffi-init-passes-correct-rows-cols ()
  "kuro--init forwards rows/cols to kuro-core-init correctly.
Verifies that the actual row and col values reach the Rust FFI,
catching regressions where dimensions might be silently dropped
or defaulted incorrectly."
  (let ((kuro--initialized nil)
        (received-args nil))
    (cl-letf (((symbol-function 'kuro-core-init)
               (lambda (cmd rows cols)
                 (setq received-args (list cmd rows cols))
                 t)))
      ;; Pass explicit rows/cols
      (kuro--init "bash" 30 120)
      (should received-args)
      (should (equal (nth 0 received-args) "bash"))
      (should (= (nth 1 received-args) 30))
      (should (= (nth 2 received-args) 120)))))

(ert-deftest kuro-ffi-init-uses-defaults-when-omitted ()
  "kuro--init uses sensible defaults (24 rows, 80 cols) when dimensions omitted."
  (let ((kuro--initialized nil)
        (received-args nil))
    (cl-letf (((symbol-function 'kuro-core-init)
               (lambda (cmd rows cols)
                 (setq received-args (list cmd rows cols))
                 t)))
      ;; Omit rows/cols — should use defaults
      (kuro--init "bash")
      (should received-args)
      (should (= (nth 1 received-args) 24))  ; default rows
      (should (= (nth 2 received-args) 80))))) ; default cols

;;; Group 3: kuro--shutdown

(ert-deftest kuro-ffi-shutdown-clears-initialized ()
  "kuro--shutdown resets kuro--initialized to nil."
  (kuro-ffi-test--with-stub kuro-core-shutdown (lambda (_id) t)
    (kuro--shutdown)
    (should-not kuro--initialized)))

(ert-deftest kuro-ffi-shutdown-returns-nil-when-not-initialized ()
  "kuro--shutdown returns nil when not initialized (guard)."
  (let ((kuro--initialized nil))
    (should-not (kuro--shutdown))))

;;; Group 4: kuro--send-key

(ert-deftest kuro-ffi-send-key-passes-string-directly ()
  "kuro--send-key passes string DATA directly to kuro-core-send-key."
  (let ((received nil))
    (kuro-ffi-test--with-stub kuro-core-send-key (lambda (_id s) (setq received s))
      (kuro--send-key "hello")
      (should (equal received "hello")))))

(ert-deftest kuro-ffi-send-key-converts-vector-to-string ()
  "kuro--send-key converts a vector of char codes to a string."
  (let ((received nil))
    (kuro-ffi-test--with-stub kuro-core-send-key (lambda (_id s) (setq received s))
      (kuro--send-key [?a ?b ?c])
      (should (stringp received))
      (should (equal received "abc")))))

(ert-deftest kuro-ffi-send-key-noop-when-not-initialized ()
  "kuro--send-key does nothing when not initialized."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key) (lambda (_id _s) (setq called t))))
      (kuro--send-key "x")
      (should-not called))))

;;; Group 5: Cursor position query (kuro--get-cursor)
;;
;; kuro--get-cursor is the only query wrapper defined in kuro-ffi.el itself.
;; kuro--get-cursor-visible / kuro--get-cursor-shape are tested in kuro-ffi-modes-test.el.
;; kuro--get-scroll-offset is tested in kuro-ffi-osc-test.el.
;; kuro--get-keyboard-flags is tested in kuro-ffi-modes-test.el.

(ert-deftest kuro-ffi-get-cursor-returns-pair ()
  "kuro--get-cursor returns a (row . col) pair from the stub."
  (kuro-ffi-test--with-stub kuro-core-get-cursor (lambda (_id) '(3 . 7))
    (let ((pos (kuro--get-cursor)))
      (should (equal pos '(3 . 7))))))

(ert-deftest kuro-ffi-get-cursor-nil-when-not-initialized ()
  "kuro--get-cursor returns nil when not initialized (not the fallback, since kuro--call uses `when')."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-cursor))))

;;; Group 6: Poll functions

(ert-deftest kuro-ffi-poll-clipboard-actions-returns-list ()
  "kuro--poll-clipboard-actions passes through the stub result."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-clipboard-actions)
               (lambda (_id) '((write . "hello")))))
      (let ((actions (kuro--poll-clipboard-actions)))
        (should (= (length actions) 1))
        (should (eq (car (car actions)) 'write))))))

;;; Group 7: Scrollback

(ert-deftest kuro-ffi-clear-scrollback-returns-nil-when-not-initialized ()
  "kuro--clear-scrollback returns nil when not initialized."
  (let ((kuro--initialized nil))
    (should-not (kuro--clear-scrollback))))

(ert-deftest kuro-ffi-clear-scrollback-calls-core-when-initialized ()
  "kuro--clear-scrollback calls kuro-core-clear-scrollback when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-clear-scrollback) (lambda (_id) (setq called t))))
      (kuro--clear-scrollback)
      (should called))))

;;; Group 8: Remaining FFI wrappers (poll-updates-with-faces, resize, is-process-alive)

(ert-deftest kuro-ffi-poll-updates-with-faces-nil-when-not-initialized ()
  "kuro--poll-updates-with-faces returns nil when not initialized."
  (let ((kuro--initialized nil))
    (should-not (kuro--poll-updates-with-faces))))

(ert-deftest kuro-ffi-poll-updates-with-faces-calls-core-when-initialized ()
  "kuro--poll-updates-with-faces calls kuro-core-poll-updates-with-faces."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-poll-updates-with-faces)
               (lambda (_id) (setq called t) '((0 "line" nil nil)))))
      (let ((result (kuro--poll-updates-with-faces)))
        (should called)
        (should (listp result))))))

(ert-deftest kuro-ffi-resize-nil-when-not-initialized ()
  "kuro--resize returns nil when not initialized."
  (let ((kuro--initialized nil))
    (should-not (kuro--resize 24 80))))

(ert-deftest kuro-ffi-resize-calls-core-with-rows-and-cols ()
  "kuro--resize forwards rows and cols to kuro-core-resize when initialized."
  (let ((kuro--initialized t)
        (received-rows nil)
        (received-cols nil))
    (cl-letf (((symbol-function 'kuro-core-resize)
               (lambda (_id rows cols)
                 (setq received-rows rows
                       received-cols cols))))
      (kuro--resize 30 120)
      (should (= received-rows 30))
      (should (= received-cols 120)))))

(ert-deftest kuro-ffi-is-process-alive-nil-when-not-initialized ()
  "kuro--is-process-alive returns nil when not initialized.
Note: the fallback in kuro--call t is NOT reached when uninitialized;
`when' short-circuits and returns nil regardless of the fallback value."
  (let ((kuro--initialized nil))
    (should-not (kuro--is-process-alive))))

(ert-deftest kuro-ffi-is-process-alive-returns-core-value-when-initialized ()
  "kuro--is-process-alive returns the value from kuro-core-is-process-alive."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-is-process-alive) (lambda (_id) t)))
      (should (kuro--is-process-alive)))
    (cl-letf (((symbol-function 'kuro-core-is-process-alive) (lambda (_id) nil)))
      (should-not (kuro--is-process-alive)))))

;;; Group 9: kuro--call error-path fallback values

(ert-deftest kuro-ffi-call-fallback-list-on-error ()
  "kuro--call returns a list fallback (not nil) when BODY signals an error.
Covers the cursor fallback path: (kuro--call \\='(0 . 0) ...)."
  (let ((kuro--initialized t))
    (should (equal '(0 . 0) (kuro--call '(0 . 0) (error "cursor fail"))))))

(ert-deftest kuro-ffi-call-fallback-t-on-error ()
  "kuro--call returns t as fallback when BODY errors.
Covers kuro--is-process-alive: it uses t as fallback to avoid spurious
buffer kills on transient FFI failures."
  (let ((kuro--initialized t))
    (should (eq t (kuro--call t (error "process check fail"))))))

(ert-deftest kuro-ffi-call-fallback-not-evaluated-when-body-succeeds ()
  "kuro--call does not evaluate side-effecting fallback form on success.
Ensures the fallback expression is not eagerly evaluated."
  (let ((kuro--initialized t)
        (fallback-evaluated nil))
    ;; The fallback is a progn that sets a flag; it must never run.
    (let ((result (kuro--call (progn (setq fallback-evaluated t) -1) 42)))
      (should (= result 42))
      (should-not fallback-evaluated))))

;;; Group 10: kuro--is-process-alive error-path returns t (not nil)

(ert-deftest kuro-ffi-is-process-alive-returns-t-on-ffi-error ()
  "kuro--is-process-alive returns t (not nil) when kuro-core-is-process-alive errors.
This is the safety fallback: assume alive to prevent spurious buffer kills."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-is-process-alive)
               (lambda (_id) (error "FFI crash"))))
      (should (kuro--is-process-alive)))))

;;; Group 11: kuro--get-cursor fallback

(ert-deftest kuro-ffi-get-cursor-returns-fallback-on-ffi-error ()
  "kuro--get-cursor returns (0 . 0) fallback when kuro-core-get-cursor errors."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-cursor)
               (lambda (_id) (error "cursor unavailable"))))
      (should (equal '(0 . 0) (kuro--get-cursor))))))

(provide 'kuro-ffi-test)

;;; kuro-ffi-test.el ends here
