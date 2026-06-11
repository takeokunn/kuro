;;; kuro-ffi-test-2.el --- Unit tests for kuro-ffi.el (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-ffi)

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

(provide 'kuro-ffi-test-2)

;;; kuro-ffi-test-2.el ends here
