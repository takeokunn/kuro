;;; kuro-ffi-ext2-test.el --- Unit tests for kuro-ffi.el (part 2)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Continuation of kuro-ffi-test.el (Groups 12–22).
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
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _r _c) 7)))
      (kuro--init "bash")
      (should (= kuro--session-id 7)))))

(ert-deftest kuro-ffi-init-does-not-change-session-id-on-nil-result ()
  "kuro--init leaves kuro--session-id unchanged when kuro-core-init returns nil."
  (let ((kuro--initialized nil)
        (kuro--session-id 5))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _r _c) nil)))
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
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (_cmd _r _c) 3)))
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

(provide 'kuro-ffi-ext2-test)

;;; kuro-ffi-ext2-test.el ends here
