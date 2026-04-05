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
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _shell-args _rows _cols) t)))
      (kuro--init "bash")
      (should kuro--initialized))))

(ert-deftest kuro-ffi-init-leaves-uninitialized-on-nil-result ()
  "kuro--init leaves kuro--initialized nil when kuro-core-init returns nil."
  (let ((kuro--initialized nil))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _shell-args _rows _cols) nil)))
      (kuro--init "bash")
      (should-not kuro--initialized))))

(ert-deftest kuro-ffi-init-returns-nil-on-error ()
  "kuro--init returns nil and does not raise when kuro-core-init errors."
  (let ((kuro--initialized nil))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _shell-args _rows _cols) (error "no PTY"))))
      (let ((result (kuro--init "bash")))
        (should-not result)
        (should-not kuro--initialized)))))

(ert-deftest kuro-ffi-init-passes-correct-rows-cols ()
  "kuro--init forwards shell-args/rows/cols to kuro-core-init correctly.
Verifies that the actual shell-args, row, and col values reach the Rust FFI,
catching regressions where dimensions might be silently dropped
or defaulted incorrectly."
  (let ((kuro--initialized nil)
        (received-args nil))
    (cl-letf (((symbol-function 'kuro-core-init)
               (lambda (cmd shell-args rows cols)
                 (setq received-args (list cmd shell-args rows cols))
                 t)))
      ;; Pass explicit shell-args / rows / cols
      (kuro--init "bash" '("--norc") 30 120)
      (should received-args)
      (should (equal (nth 0 received-args) "bash"))
      (should (equal (nth 1 received-args) '("--norc")))
      (should (= (nth 2 received-args) 30))
      (should (= (nth 3 received-args) 120)))))

(ert-deftest kuro-ffi-init-ensures-module-loaded-before-core-init ()
  "kuro--init loads the native module before calling kuro-core-init.
This keeps direct callers such as the E2E harness on the real Elisp↔Rust path
instead of failing with a void-function error when the module is available but
has not been loaded yet."
  (let ((kuro--initialized nil)
        (call-order nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded)
               (lambda () (push 'ensure call-order)))
              ((symbol-function 'kuro-core-init)
               (lambda (_cmd _shell-args _rows _cols)
                 (push 'init call-order)
                 t)))
      (kuro--init "bash")
      (should (equal (reverse call-order) '(ensure init))))))

(ert-deftest kuro-ffi-init-uses-defaults-when-omitted ()
  "kuro--init uses sensible defaults (24 rows, 80 cols) when dimensions omitted."
  (let ((kuro--initialized nil)
        (received-args nil))
    (cl-letf (((symbol-function 'kuro-core-init)
               (lambda (cmd shell-args rows cols)
                 (setq received-args (list cmd shell-args rows cols))
                 t)))
      ;; Omit shell-args/rows/cols — should use defaults
      (kuro--init "bash")
      (should received-args)
      (should (= (nth 2 received-args) 24))  ; default rows
      (should (= (nth 3 received-args) 80))))) ; default cols

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

;;; Group 12: kuro--shutdown return value and session-id reset

(ert-deftest kuro-ffi-shutdown-returns-t-on-success ()
  "kuro--shutdown returns t when the Rust shutdown call succeeds."
  (kuro-ffi-test--with-stub kuro-core-shutdown (lambda (_id) t)
    (should (eq t (kuro--shutdown)))))

(ert-deftest kuro-ffi-shutdown-resets-session-id-to-zero ()
  "kuro--shutdown resets kuro--session-id to 0 after a successful shutdown."
  (let ((kuro--session-id 42))
    (kuro-ffi-test--with-stub kuro-core-shutdown (lambda (_id) t)
      (kuro--shutdown)
      (should (= kuro--session-id 0)))))

;;; Group 13: kuro--init session-id assignment

(ert-deftest kuro-ffi-init-stores-session-id-from-core ()
  "kuro--init stores the integer returned by kuro-core-init as kuro--session-id."
  (let ((kuro--initialized nil)
        (kuro--session-id 0))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _sa _r _c) 7)))
      (kuro--init "bash")
      (should (= kuro--session-id 7)))))

(ert-deftest kuro-ffi-init-does-not-change-session-id-on-nil-result ()
  "kuro--init leaves kuro--session-id unchanged when kuro-core-init returns nil."
  (let ((kuro--initialized nil)
        (kuro--session-id 5))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _sa _r _c) nil)))
      (kuro--init "bash")
      (should (= kuro--session-id 5)))))

;;; Group 14: kuro--resize edge cases

(ert-deftest kuro-ffi-resize-zero-rows-zero-cols ()
  "kuro--resize forwards 0 rows and 0 cols to kuro-core-resize without error."
  (let ((kuro--initialized t)
        (received nil))
    (cl-letf (((symbol-function 'kuro-core-resize)
               (lambda (_id rows cols) (setq received (cons rows cols)))))
      (kuro--resize 0 0)
      (should (equal received '(0 . 0))))))

(ert-deftest kuro-ffi-resize-large-dimensions ()
  "kuro--resize forwards very large row/col values to kuro-core-resize without error."
  (let ((kuro--initialized t)
        (received nil))
    (cl-letf (((symbol-function 'kuro-core-resize)
               (lambda (_id rows cols) (setq received (cons rows cols)))))
      (kuro--resize 9999 9999)
      (should (equal received '(9999 . 9999))))))

(ert-deftest kuro-ffi-resize-returns-nil-on-ffi-error ()
  "kuro--resize returns nil when kuro-core-resize signals an error."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-resize)
               (lambda (_id _rows _cols) (error "resize failed"))))
      (should-not (kuro--resize 24 80)))))

;;; Group 15: kuro--send-key edge cases

(ert-deftest kuro-ffi-send-key-empty-string ()
  "kuro--send-key passes an empty string through to kuro-core-send-key."
  (let ((received :not-set))
    (kuro-ffi-test--with-stub kuro-core-send-key (lambda (_id s) (setq received s))
      (kuro--send-key "")
      (should (equal received "")))))

(ert-deftest kuro-ffi-send-key-empty-vector ()
  "kuro--send-key converts an empty vector to an empty string."
  (let ((received :not-set))
    (kuro-ffi-test--with-stub kuro-core-send-key (lambda (_id s) (setq received s))
      (kuro--send-key [])
      (should (stringp received))
      (should (string= received "")))))

(ert-deftest kuro-ffi-send-key-returns-nil-on-ffi-error ()
  "kuro--send-key returns nil when kuro-core-send-key signals an error."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_id _s) (error "send failed"))))
      (should-not (kuro--send-key "x")))))

;;; Group 16: kuro--poll-updates-with-faces error path

(ert-deftest kuro-ffi-poll-updates-with-faces-returns-nil-on-ffi-error ()
  "kuro--poll-updates-with-faces returns nil when the Rust call errors."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-updates-with-faces)
               (lambda (_id) (error "poll failed"))))
      (should-not (kuro--poll-updates-with-faces)))))

;;; Group 17: kuro--defvar-permanent-local macro

(ert-deftest kuro-ffi-defvar-permanent-local-sets-permanent-local-property ()
  "kuro--defvar-permanent-local marks the variable with the permanent-local property.
Verifies that the macro sets \\='permanent-local on the symbol so that the
variable survives `kill-all-local-variables' (called on major-mode activation)."
  ;; kuro--initialized and kuro--session-id are defined via the macro in kuro-ffi.el.
  (should (get 'kuro--initialized 'permanent-local))
  (should (get 'kuro--session-id 'permanent-local))
  (should (get 'kuro--col-to-buf-map 'permanent-local))
  (should (get 'kuro--resize-pending 'permanent-local)))

;;; Group 18: kuro--def-ffi-getter / kuro--def-ffi-unary macro properties
;;
;; These tests verify that the two definition macros produce real `defun' forms
;; with accessible docstrings, correct arities, and correct fallback behaviour
;; without relying on any pre-existing wrapper defined outside kuro-ffi.el.

(ert-deftest kuro-ffi-def-ffi-getter-produces-zero-arity-function ()
  "kuro--def-ffi-getter generates a zero-argument `defun'."
  ;; kuro--get-cursor is defined in kuro-ffi.el via a plain defun, but
  ;; kuro--get-scroll-offset (defined via kuro--def-ffi-getter in
  ;; kuro-ffi-osc.el) is not available here.  Use the macro directly.
  (kuro--def-ffi-getter kuro--test-getter-arity
    kuro-core-get-cursor nil
    "Test getter produced by kuro--def-ffi-getter.")
  (should (fboundp 'kuro--test-getter-arity))
  ;; Zero required arguments — function is callable with no args.
  (let ((kuro--initialized nil))
    (should-not (kuro--test-getter-arity))))

(ert-deftest kuro-ffi-def-ffi-getter-docstring-is-accessible ()
  "kuro--def-ffi-getter stores the DOC argument as a real docstring."
  (kuro--def-ffi-getter kuro--test-getter-doc
    kuro-core-get-cursor nil
    "Unique docstring for getter docstring test XYZZY123.")
  (let ((doc (documentation 'kuro--test-getter-doc)))
    (should (stringp doc))
    (should (string-match-p "XYZZY123" doc))))

(ert-deftest kuro-ffi-def-ffi-unary-produces-one-arity-function ()
  "kuro--def-ffi-unary generates a one-argument `defun'."
  (kuro--def-ffi-unary kuro--test-unary-arity
    kuro-core-resize nil rows
    "Test unary function produced by kuro--def-ffi-unary.")
  (should (fboundp 'kuro--test-unary-arity))
  ;; One required argument — callable with one arg when uninitialized.
  (let ((kuro--initialized nil))
    (should-not (kuro--test-unary-arity 24))))

(ert-deftest kuro-ffi-def-ffi-unary-forwards-arg-to-core ()
  "kuro--def-ffi-unary passes the caller-supplied argument to the core function."
  (kuro--def-ffi-unary kuro--test-unary-fwd
    kuro-core-resize nil my-arg
    "Test unary forwarding.")
  (let ((kuro--initialized t)
        (received :not-set))
    (cl-letf (((symbol-function 'kuro-core-resize)
               (lambda (_sid v) (setq received v))))
      (kuro--test-unary-fwd 42)
      (should (= received 42)))))

(ert-deftest kuro-ffi-def-ffi-getter-returns-fallback-on-ffi-error ()
  "kuro--def-ffi-getter returns the declared fallback when the core fn errors."
  (kuro--def-ffi-getter kuro--test-getter-fallback
    kuro-core-get-cursor :my-fallback
    "Test getter fallback.")
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-cursor)
               (lambda (_id) (error "getter error"))))
      (should (eq :my-fallback (kuro--test-getter-fallback))))))

(ert-deftest kuro-ffi-init-returns-session-id-integer-on-success ()
  "kuro--init returns the integer session-id (not just t) when kuro-core-init succeeds."
  (let ((kuro--initialized nil)
        (kuro--session-id 0))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _sa _r _c) 3)))
      (let ((result (kuro--init "bash")))
        (should (integerp result))
        (should (= result 3))))))

(ert-deftest kuro-ffi-shutdown-returns-nil-on-ffi-error ()
  "kuro--shutdown returns nil when kuro-core-shutdown signals an error."
  (let ((kuro--initialized t)
        (kuro--session-id 1))
    (cl-letf (((symbol-function 'kuro-core-shutdown)
               (lambda (_id) (error "shutdown error"))))
      (should-not (kuro--shutdown)))))

;;; Group 19: kuro--defvar-permanent-local — buffer-locality and default value

(ert-deftest kuro-ffi-defvar-permanent-local-var-is-buffer-local ()
  "kuro--defvar-permanent-local creates a buffer-local variable."
  ;; Variables defined by the macro must be buffer-local so that each
  ;; kuro buffer tracks its own state independently.
  (should (local-variable-if-set-p 'kuro--initialized))
  (should (local-variable-if-set-p 'kuro--session-id))
  (should (local-variable-if-set-p 'kuro--col-to-buf-map))
  (should (local-variable-if-set-p 'kuro--resize-pending)))

(ert-deftest kuro-ffi-defvar-permanent-local-session-id-default-zero ()
  "kuro--session-id has a default value of 0 in a fresh buffer."
  (with-temp-buffer
    (should (= kuro--session-id 0))))

(ert-deftest kuro-ffi-defvar-permanent-local-initialized-default-nil ()
  "kuro--initialized has a default value of nil in a fresh buffer."
  (with-temp-buffer
    (should-not kuro--initialized)))

(ert-deftest kuro-ffi-defvar-permanent-local-col-to-buf-map-is-hash-table ()
  "kuro--col-to-buf-map default value is a hash table."
  (with-temp-buffer
    (should (hash-table-p kuro--col-to-buf-map))))

(ert-deftest kuro-ffi-defvar-permanent-local-resize-pending-default-nil ()
  "kuro--resize-pending has a default value of nil in a fresh buffer."
  (with-temp-buffer
    (should-not kuro--resize-pending)))

;;; Group 20: kuro--def-ffi-unary — error fallback and uninitialized guard

(ert-deftest kuro-ffi-def-ffi-unary-returns-fallback-on-ffi-error ()
  "kuro--def-ffi-unary returns the declared fallback when the core fn errors."
  (kuro--def-ffi-unary kuro--test-unary-fallback
    kuro-core-resize :unary-fallback my-arg
    "Test unary fallback on error.")
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-resize)
               (lambda (_sid _v) (error "unary error"))))
      (should (eq :unary-fallback (kuro--test-unary-fallback 99))))))

(ert-deftest kuro-ffi-def-ffi-unary-returns-nil-when-not-initialized ()
  "kuro--def-ffi-unary returns nil when kuro--initialized is nil.
Note: kuro--call uses `when', so nil is returned regardless of fallback."
  (kuro--def-ffi-unary kuro--test-unary-uninit
    kuro-core-resize :should-not-appear my-arg
    "Test unary guard when not initialized.")
  (let ((kuro--initialized nil))
    (should-not (kuro--test-unary-uninit 5))))

(ert-deftest kuro-ffi-def-ffi-unary-docstring-is-accessible ()
  "kuro--def-ffi-unary stores the DOC argument as a real docstring."
  (kuro--def-ffi-unary kuro--test-unary-doc
    kuro-core-resize nil my-arg
    "Unique docstring for unary docstring test PLUGH456.")
  (let ((doc (documentation 'kuro--test-unary-doc)))
    (should (stringp doc))
    (should (string-match-p "PLUGH456" doc))))

;;; Group 21: kuro--shutdown — session-id behavior on error and isolation

(ert-deftest kuro-ffi-shutdown-does-not-reset-session-id-on-ffi-error ()
  "kuro--shutdown leaves kuro--session-id unchanged when the Rust call errors.
The session-id reset only happens inside the protected body, so an error
aborts before the reset takes effect."
  (let ((kuro--initialized t)
        (kuro--session-id 99))
    (cl-letf (((symbol-function 'kuro-core-shutdown)
               (lambda (_id) (error "shutdown error"))))
      (kuro--shutdown)
      ;; session-id not reset because error was caught before the reset
      (should (= kuro--session-id 99)))))

(ert-deftest kuro-ffi-shutdown-leaves-initialized-true-on-ffi-error ()
  "kuro--shutdown leaves kuro--initialized t when the Rust call errors.
The `(setq kuro--initialized nil)' runs after the Rust call, so an error
before it means initialized is still t."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-shutdown)
               (lambda (_id) (error "shutdown error"))))
      (kuro--shutdown)
      ;; kuro--initialized NOT cleared because error fired before the setq
      (should kuro--initialized))))

(ert-deftest kuro-ffi-shutdown-passes-correct-session-id ()
  "kuro--shutdown passes the current kuro--session-id to kuro-core-shutdown."
  (let ((kuro--initialized t)
        (kuro--session-id 42)
        (received-id nil))
    (cl-letf (((symbol-function 'kuro-core-shutdown)
               (lambda (id) (setq received-id id) t)))
      (kuro--shutdown)
      (should (= received-id 42)))))

;;; Group 22: kuro--when-divisible — cadence-gating primitive

(ert-deftest kuro-ffi-when-divisible-fires-at-zero ()
  (let ((ran nil))
    (kuro--when-divisible 0 5 (setq ran t))
    (should ran)))

(ert-deftest kuro-ffi-when-divisible-fires-at-multiple ()
  (let ((ran nil))
    (kuro--when-divisible 10 5 (setq ran t))
    (should ran)))

(ert-deftest kuro-ffi-when-divisible-skips-non-multiple ()
  (let ((ran nil))
    (kuro--when-divisible 7 5 (setq ran t))
    (should-not ran)))

(ert-deftest kuro-ffi-when-divisible-returns-nil-when-skipped ()
  (should-not (kuro--when-divisible 7 5 t)))

(ert-deftest kuro-ffi-when-divisible-evaluates-body-once ()
  (let ((count 0))
    (kuro--when-divisible 10 5 (setq count (1+ count)))
    (should (= count 1))))

;;; Group 23: kuro--log and kuro-log-errors

(ert-deftest kuro-ffi-call-logs-error-when-kuro-log-errors-enabled ()
  "kuro--call logs to *kuro-log* when kuro-log-errors is t and BODY errors."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil (error "test-log-error"))
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (should buf)
      (should (string-match-p "ERROR: test-log-error"
                              (with-current-buffer buf (buffer-string))))
      (kill-buffer buf))))

(ert-deftest kuro-ffi-call-does-not-log-when-kuro-log-errors-disabled ()
  "kuro--call does not log when kuro-log-errors is nil."
  (let ((kuro--initialized t)
        (kuro-log-errors nil))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil (error "should-not-appear"))
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (when buf
        (should (string= "" (with-current-buffer buf (buffer-string))))
        (kill-buffer buf)))))

(ert-deftest kuro-ffi-call-does-not-log-on-success ()
  "kuro--call does not write to *kuro-log* when BODY succeeds."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil 42)
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (if buf
          (progn
            (should (string= "" (with-current-buffer buf (buffer-string))))
            (kill-buffer buf))
        (should-not buf)))))

(ert-deftest kuro-ffi-log-buffer-uses-special-mode ()
  "The *kuro-log* buffer uses special-mode (read-only)."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil (error "mode-test"))
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (should buf)
      (with-current-buffer buf
        (should (derived-mode-p 'special-mode))
        (should buffer-read-only))
      (kill-buffer buf))))

(ert-deftest kuro-ffi-log-entries-have-timestamp-format ()
  "Each log entry has [HH:MM:SS] timestamp prefix."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil (error "timestamp-test"))
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (should buf)
      (should (string-match-p "^\\[[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\] ERROR:"
                              (with-current-buffer buf (buffer-string))))
      (kill-buffer buf))))

(ert-deftest kuro-ffi-show-log-creates-buffer ()
  "kuro-show-log creates the *kuro-log* buffer if it does not exist."
  (when (get-buffer kuro--log-buffer-name)
    (kill-buffer kuro--log-buffer-name))
  (save-window-excursion
    (kuro-show-log))
  (let ((buf (get-buffer kuro--log-buffer-name)))
    (should buf)
    (with-current-buffer buf
      (should (derived-mode-p 'special-mode)))
    (kill-buffer buf)))

(ert-deftest kuro-ffi-call-still-returns-fallback-when-logging ()
  "kuro--call returns fallback value even when logging is enabled."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (should (= -1 (kuro--call -1 (error "fallback-with-log"))))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))))

;;; Group 24: kuro-show-log

(ert-deftest kuro-ffi-show-log-calls-display-buffer ()
  "kuro-show-log calls `display-buffer' with the log buffer."
  (let ((display-called-with nil))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (cl-letf (((symbol-function 'display-buffer)
               (lambda (buf) (setq display-called-with buf))))
      (kuro-show-log))
    (should display-called-with)
    (should (bufferp display-called-with))
    (should (string= (buffer-name display-called-with) kuro--log-buffer-name))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))))

(ert-deftest kuro-ffi-show-log-idempotent-special-mode ()
  "Calling kuro-show-log twice leaves *kuro-log* in special-mode."
  (when (get-buffer kuro--log-buffer-name)
    (kill-buffer kuro--log-buffer-name))
  (cl-letf (((symbol-function 'display-buffer) #'ignore))
    (kuro-show-log)
    (kuro-show-log))
  (let ((buf (get-buffer kuro--log-buffer-name)))
    (should buf)
    (with-current-buffer buf
      (should (derived-mode-p 'special-mode)))
    (kill-buffer buf)))

(ert-deftest kuro-ffi-show-log-buffer-name-matches-constant ()
  "kuro-show-log creates a buffer whose name equals kuro--log-buffer-name."
  (when (get-buffer kuro--log-buffer-name)
    (kill-buffer kuro--log-buffer-name))
  (cl-letf (((symbol-function 'display-buffer) #'ignore))
    (kuro-show-log))
  (let ((buf (get-buffer kuro--log-buffer-name)))
    (should buf)
    (should (string= (buffer-name buf) kuro--log-buffer-name))
    (kill-buffer buf)))

;;; Group 25: kuro--log buffer truncation

(ert-deftest kuro-ffi-ext-log-truncation-removes-oldest-content ()
  "After truncation, the oldest content (inserted before overflow) is gone."
  (let ((kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (unwind-protect
        (let ((buf (get-buffer-create kuro--log-buffer-name)))
          (with-current-buffer buf
            (unless (derived-mode-p 'special-mode) (special-mode))
            (let ((inhibit-read-only t))
              ;; Insert a sentinel string at the very beginning, then pad the
              ;; buffer past kuro--log-max-size so the next kuro--log call
              ;; triggers deletion of the oldest half.
              (insert "OLDEST-SENTINEL\n")
              (insert (make-string kuro--log-max-size ?x))
              (insert "\n")))
          ;; One more log call should trigger truncation.
          (kuro--log '(error "truncation-trigger"))
          (let ((content (with-current-buffer buf (buffer-string))))
            (should-not (string-match-p "OLDEST-SENTINEL" content))))
      (when (get-buffer kuro--log-buffer-name)
        (kill-buffer kuro--log-buffer-name)))))

(ert-deftest kuro-ffi-ext-log-truncation-preserves-newest-content ()
  "After truncation, the entry that triggered truncation is still present."
  (let ((kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (unwind-protect
        (let ((buf (get-buffer-create kuro--log-buffer-name)))
          (with-current-buffer buf
            (unless (derived-mode-p 'special-mode) (special-mode))
            (let ((inhibit-read-only t))
              (insert (make-string (1+ kuro--log-max-size) ?y))
              (insert "\n")))
          (kuro--log '(error "NEWEST-SENTINEL"))
          (let ((content (with-current-buffer buf (buffer-string))))
            (should (string-match-p "NEWEST-SENTINEL" content))))
      (when (get-buffer kuro--log-buffer-name)
        (kill-buffer kuro--log-buffer-name)))))

(ert-deftest kuro-ffi-ext-log-truncation-reduces-size-below-max ()
  "After truncation the buffer size is at most kuro--log-max-size bytes."
  (let ((kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (unwind-protect
        (let ((buf (get-buffer-create kuro--log-buffer-name)))
          (with-current-buffer buf
            (unless (derived-mode-p 'special-mode) (special-mode))
            (let ((inhibit-read-only t))
              ;; Fill to exactly twice the max so the post-truncation size is
              ;; kuro--log-max-size/2 + the new entry (a short line), still
              ;; well under kuro--log-max-size.
              (insert (make-string (* 2 kuro--log-max-size) ?z))
              (insert "\n")))
          (kuro--log '(error "size-check"))
          (should (< (with-current-buffer buf (buffer-size))
                     kuro--log-max-size)))
      (when (get-buffer kuro--log-buffer-name)
        (kill-buffer kuro--log-buffer-name)))))

(ert-deftest kuro-ffi-ext-log-truncation-fires-at-threshold ()
  "Truncation fires when buffer size is just over kuro--log-max-size."
  (let ((kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (unwind-protect
        (let ((buf (get-buffer-create kuro--log-buffer-name)))
          (with-current-buffer buf
            (unless (derived-mode-p 'special-mode) (special-mode))
            (let ((inhibit-read-only t))
              ;; Fill to exactly kuro--log-max-size; the new kuro--log entry
              ;; will push it just over the threshold.
              (insert "AT-THRESHOLD-MARKER\n")
              (insert (make-string kuro--log-max-size ?t))))
          ;; This call should push size over max and trigger truncation.
          (kuro--log '(error "threshold-entry"))
          ;; The old sentinel written before the pad should be gone.
          (let ((content (with-current-buffer buf (buffer-string))))
            (should-not (string-match-p "AT-THRESHOLD-MARKER" content))))
      (when (get-buffer kuro--log-buffer-name)
        (kill-buffer kuro--log-buffer-name)))))

(provide 'kuro-ffi-test)

;;; kuro-ffi-test.el ends here
