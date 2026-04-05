;;; kuro-ffi-osc-test.el --- Unit tests for kuro-ffi-osc.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-ffi-osc.el (OSC event wrappers and helpers).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; kuro--update-prompt-positions tests moved to kuro-navigation-test.el
;; (Group 5) in Round 20 restructure.  This file covers:
;; kuro--initialized=nil guard for all 17 FFI wrappers.

;;; Code:

(require 'ert)
(require 'seq)

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (unit-dir (expand-file-name ".." this-dir)))
  (add-to-list 'load-path unit-dir))
(require 'kuro-test-stubs)

;; Stub defcustom variables that kuro-config.el would normally define.
(defvar kuro--initialized nil)

(require 'kuro-ffi-osc)
(require 'kuro-navigation)

;;; Test helper macro

(defmacro kuro-ffi-osc-test--uninit-nil (sym &rest args)
  "Define an ert-deftest asserting (SYM ARGS...) returns nil when uninit.
SYM must be a kuro-- prefixed symbol; the test is named by stripping that prefix."
  (let* ((bare (replace-regexp-in-string "^kuro--" "" (symbol-name sym)))
         (test-name (intern (format "kuro-ffi-osc-%s-nil-when-uninit" bare))))
    `(ert-deftest ,test-name ()
       ,(format "%s returns nil when kuro--initialized is nil." sym)
       (let ((kuro--initialized nil))
         (should-not (,sym ,@args))))))

;;; Group 1: kuro--initialized=nil guard path
;;
;; When `kuro--initialized' is nil, the `kuro--call' macro expands to
;; (when nil ...) which short-circuits and returns nil unconditionally —
;; regardless of the declared fallback value.  Every wrapper must honour this.

(kuro-ffi-osc-test--uninit-nil kuro--get-and-clear-title)
(kuro-ffi-osc-test--uninit-nil kuro--get-cwd)
(kuro-ffi-osc-test--uninit-nil kuro--poll-clipboard-actions)
(kuro-ffi-osc-test--uninit-nil kuro--poll-prompt-marks)
(kuro-ffi-osc-test--uninit-nil kuro--get-image 0)
(kuro-ffi-osc-test--uninit-nil kuro--poll-image-notifications)
(kuro-ffi-osc-test--uninit-nil kuro--consume-scroll-events)
(kuro-ffi-osc-test--uninit-nil kuro--has-pending-output)
(kuro-ffi-osc-test--uninit-nil kuro--get-palette-updates)
(kuro-ffi-osc-test--uninit-nil kuro--get-default-colors)
(kuro-ffi-osc-test--uninit-nil kuro--get-scrollback 100)
(kuro-ffi-osc-test--uninit-nil kuro--clear-scrollback)
(kuro-ffi-osc-test--uninit-nil kuro--set-scrollback-max-lines 1000)
(kuro-ffi-osc-test--uninit-nil kuro--get-scrollback-count)
(kuro-ffi-osc-test--uninit-nil kuro--scroll-up 1)
(kuro-ffi-osc-test--uninit-nil kuro--scroll-down 1)
(kuro-ffi-osc-test--uninit-nil kuro--get-scroll-offset)
(kuro-ffi-osc-test--uninit-nil kuro--poll-eval-commands)
(kuro-ffi-osc-test--uninit-nil kuro--get-cwd-host)

;;; Group 2 helper macro

(defmacro kuro-ffi-osc-test--init-delegates (func-sym core-sym retval &rest call-args)
  "Define ert-deftest verifying FUNC-SYM delegates to CORE-SYM when initialized.
RETVAL is returned by the stub.  CALL-ARGS (if any) are forwarded to FUNC-SYM.
No-arg form: verifies stub was called via a `called' flag.
Arg-passthrough form: verifies args were forwarded via `received' list.
Test name: kuro-ffi-osc-BARE-calls-core-when-init (BARE = name minus kuro-- prefix)."
  (let* ((bare (replace-regexp-in-string "^kuro--" "" (symbol-name func-sym)))
         (test-name (intern (format "kuro-ffi-osc-%s-calls-core-when-init" bare))))
    (if call-args
        `(ert-deftest ,test-name ()
           ,(format "%s delegates to %s and forwards its arguments." func-sym core-sym)
           (let ((kuro--initialized t)
                 (received nil))
             (cl-letf (((symbol-function ',core-sym)
                        (lambda (_id &rest args) (setq received args) ,retval)))
               (let ((result (,func-sym ,@call-args)))
                 (should (equal received (list ,@call-args)))
                 (should (equal result ,retval))))))
      `(ert-deftest ,test-name ()
         ,(format "%s delegates to %s when initialized." func-sym core-sym)
         (let ((kuro--initialized t)
               (called nil))
           (cl-letf (((symbol-function ',core-sym)
                      (lambda (_id) (setq called t) ,retval)))
             (let ((result (,func-sym)))
               (should called)
               (should (equal result ,retval)))))))))

;;; Group 2: kuro--initialized=t calls the underlying core function
;;
;; Each wrapper must delegate to its kuro-core-* counterpart when initialized.
;; cl-letf stubs the core function; tests verify both that the stub was called
;; and that the return value is passed through unchanged.

(kuro-ffi-osc-test--init-delegates kuro--get-and-clear-title   kuro-core-get-and-clear-title   "test-title")
(kuro-ffi-osc-test--init-delegates kuro--get-cwd               kuro-core-get-cwd               "/home/user")
(kuro-ffi-osc-test--init-delegates kuro--poll-clipboard-actions kuro-core-poll-clipboard-actions '((write . "hello")))
(kuro-ffi-osc-test--init-delegates kuro--poll-prompt-marks     kuro-core-poll-prompt-marks     '((0 . prompt-start)))
(kuro-ffi-osc-test--init-delegates kuro--get-image             kuro-core-get-image             "base64data"            42)
(kuro-ffi-osc-test--init-delegates kuro--poll-image-notifications kuro-core-poll-image-notifications '((1 0 0 10 5)))
(kuro-ffi-osc-test--init-delegates kuro--consume-scroll-events kuro-core-consume-scroll-events '(2 . 0))
(kuro-ffi-osc-test--init-delegates kuro--has-pending-output    kuro-core-has-pending-output    t)
(kuro-ffi-osc-test--init-delegates kuro--get-palette-updates   kuro-core-get-palette-updates   '((1 255 0 0)))
(kuro-ffi-osc-test--init-delegates kuro--get-default-colors    kuro-core-get-default-colors    '(#xFFFFFF #x000000 #xAAAAAA))
(kuro-ffi-osc-test--init-delegates kuro--get-scrollback        kuro-core-get-scrollback        '("line1" "line2")       100)
(kuro-ffi-osc-test--init-delegates kuro--clear-scrollback      kuro-core-clear-scrollback      t)
(kuro-ffi-osc-test--init-delegates kuro--set-scrollback-max-lines kuro-core-set-scrollback-max-lines t                 1000)
(kuro-ffi-osc-test--init-delegates kuro--get-scrollback-count  kuro-core-get-scrollback-count  42)
(kuro-ffi-osc-test--init-delegates kuro--scroll-up             kuro-core-scroll-up             t                       3)
(kuro-ffi-osc-test--init-delegates kuro--scroll-down           kuro-core-scroll-down           t                       5)
(kuro-ffi-osc-test--init-delegates kuro--get-scroll-offset     kuro-core-get-scroll-offset     7)
(kuro-ffi-osc-test--init-delegates kuro--poll-eval-commands    kuro-core-poll-eval-commands    '("(cd \"/tmp\")"))
(kuro-ffi-osc-test--init-delegates kuro--get-cwd-host          kuro-core-get-cwd-host          "remote-host")

;;; Group 3: Behavioral / value semantics when initialized
;;
;; These tests verify the exact shapes of return values, edge cases for
;; numeric arguments, and the zero-vs-nil distinction for functions whose
;; documented fallback is 0.

(ert-deftest kuro-ffi-osc-consume-scroll-events-nil-result-when-no-scroll ()
  "kuro--consume-scroll-events returns nil (not a cons) when stub returns nil."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda (_id) nil)))
      (should-not (kuro--consume-scroll-events)))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-cons-pair-up-only ()
  "kuro--consume-scroll-events returns (N . 0) when only up-scroll occurred."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda (_id) '(3 . 0))))
      (let ((result (kuro--consume-scroll-events)))
        (should (consp result))
        (should (= (car result) 3))
        (should (= (cdr result) 0))))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-cons-pair-down-only ()
  "kuro--consume-scroll-events returns (0 . N) when only down-scroll occurred."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda (_id) '(0 . 5))))
      (let ((result (kuro--consume-scroll-events)))
        (should (consp result))
        (should (= (car result) 0))
        (should (= (cdr result) 5))))))

(ert-deftest kuro-ffi-osc-has-pending-output-returns-t-when-data-waiting ()
  "kuro--has-pending-output returns t when stub signals data available."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-has-pending-output)
               (lambda (_id) t)))
      (should (eq t (kuro--has-pending-output))))))

(ert-deftest kuro-ffi-osc-has-pending-output-returns-nil-when-no-data ()
  "kuro--has-pending-output returns nil when stub returns nil (buffer drained)."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-has-pending-output)
               (lambda (_id) nil)))
      (should-not (kuro--has-pending-output)))))

(ert-deftest kuro-ffi-osc-get-scrollback-returns-list-of-strings ()
  "kuro--get-scrollback returns a list of strings from the stub."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback)
               (lambda (_id _n) '("alpha" "beta" "gamma"))))
      (let ((result (kuro--get-scrollback 3)))
        (should (listp result))
        (should (= (length result) 3))
        (should (string= (car result) "alpha"))))))

(ert-deftest kuro-ffi-osc-get-scrollback-returns-nil-when-buffer-empty ()
  "kuro--get-scrollback returns nil when scrollback buffer is empty."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback)
               (lambda (_id _n) nil)))
      (should-not (kuro--get-scrollback 100)))))

(ert-deftest kuro-ffi-osc-get-scrollback-forwards-max-lines-argument ()
  "kuro--get-scrollback passes the max-lines argument verbatim to the core fn."
  (let ((kuro--initialized t)
        (captured-max nil))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback)
               (lambda (_id n) (setq captured-max n) nil)))
      (kuro--get-scrollback 500)
      (should (= captured-max 500)))))

(ert-deftest kuro-ffi-osc-set-scrollback-max-lines-forwards-argument ()
  "kuro--set-scrollback-max-lines forwards the max-lines argument to core."
  (let ((kuro--initialized t)
        (captured-n nil))
    (cl-letf (((symbol-function 'kuro-core-set-scrollback-max-lines)
               (lambda (_id n) (setq captured-n n) t)))
      (kuro--set-scrollback-max-lines 2000)
      (should (= captured-n 2000)))))

(ert-deftest kuro-ffi-osc-set-scrollback-max-lines-returns-t-on-success ()
  "kuro--set-scrollback-max-lines returns t when the core function succeeds."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-set-scrollback-max-lines)
               (lambda (_id _n) t)))
      (should (eq t (kuro--set-scrollback-max-lines 1000))))))

(ert-deftest kuro-ffi-osc-scroll-up-forwards-session-id ()
  "kuro--scroll-up passes kuro--session-id as first arg to core function."
  (let ((kuro--initialized t)
        (kuro--session-id 7)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-scroll-up)
               (lambda (sid _n) (setq captured-sid sid) t)))
      (kuro--scroll-up 1)
      (should (= captured-sid 7)))))

(ert-deftest kuro-ffi-osc-scroll-down-forwards-session-id ()
  "kuro--scroll-down passes kuro--session-id as first arg to core function."
  (let ((kuro--initialized t)
        (kuro--session-id 9)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-scroll-down)
               (lambda (sid _n) (setq captured-sid sid) t)))
      (kuro--scroll-down 2)
      (should (= captured-sid 9)))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-returns-zero-when-at-bottom ()
  "kuro--get-scroll-offset returns 0 (not nil) when core reports offset 0."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scroll-offset)
               (lambda (_id) 0)))
      (should (= 0 (kuro--get-scroll-offset))))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-returns-nil-not-zero-when-uninit ()
  "kuro--get-scroll-offset returns nil (not 0) when kuro--initialized is nil.
The fallback is 0, but kuro--call uses `when' so nil is returned when uninit."
  (let ((kuro--initialized nil))
    (should (null (kuro--get-scroll-offset)))))

(ert-deftest kuro-ffi-osc-poll-image-notifications-returns-list ()
  "kuro--poll-image-notifications returns a list of image descriptors."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-image-notifications)
               (lambda (_id) '((10 0 0 8 4) (11 1 0 8 4)))))
      (let ((result (kuro--poll-image-notifications)))
        (should (listp result))
        (should (= (length result) 2))
        (should (= (car (car result)) 10))))))

(ert-deftest kuro-ffi-osc-poll-image-notifications-returns-nil-when-none ()
  "kuro--poll-image-notifications returns nil when no images are pending."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-image-notifications)
               (lambda (_id) nil)))
      (should-not (kuro--poll-image-notifications)))))

(ert-deftest kuro-ffi-osc-get-scrollback-session-id-forwarded ()
  "kuro--get-scrollback passes kuro--session-id as first arg to core function."
  (let ((kuro--initialized t)
        (kuro--session-id 3)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback)
               (lambda (sid _n) (setq captured-sid sid) nil)))
      (kuro--get-scrollback 10)
      (should (= captured-sid 3)))))

;;; Group 4: kuro--session-id forwarding for remaining wrappers
;;
;; Each zero-argument getter passes kuro--session-id as the sole argument to
;; its core function.  Tests bind kuro--session-id to a distinctive integer
;; and verify the stub receives it, catching regressions where a wrapper might
;; inadvertently pass a hardcoded 0.

(ert-deftest kuro-ffi-osc-get-and-clear-title-forwards-session-id ()
  "kuro--get-and-clear-title passes kuro--session-id to kuro-core-get-and-clear-title."
  (let ((kuro--initialized t)
        (kuro--session-id 11)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-and-clear-title)
               (lambda (sid) (setq captured-sid sid) "title")))
      (kuro--get-and-clear-title)
      (should (= captured-sid 11)))))

(ert-deftest kuro-ffi-osc-get-cwd-forwards-session-id ()
  "kuro--get-cwd passes kuro--session-id to kuro-core-get-cwd."
  (let ((kuro--initialized t)
        (kuro--session-id 22)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-cwd)
               (lambda (sid) (setq captured-sid sid) "/tmp")))
      (kuro--get-cwd)
      (should (= captured-sid 22)))))

(ert-deftest kuro-ffi-osc-poll-clipboard-actions-forwards-session-id ()
  "kuro--poll-clipboard-actions passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 33)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-poll-clipboard-actions)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--poll-clipboard-actions)
      (should (= captured-sid 33)))))

(ert-deftest kuro-ffi-osc-poll-prompt-marks-forwards-session-id ()
  "kuro--poll-prompt-marks passes kuro--session-id to kuro-core-poll-prompt-marks."
  (let ((kuro--initialized t)
        (kuro--session-id 44)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-poll-prompt-marks)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--poll-prompt-marks)
      (should (= captured-sid 44)))))

(ert-deftest kuro-ffi-osc-get-image-forwards-session-id ()
  "kuro--get-image passes kuro--session-id as first arg to kuro-core-get-image."
  (let ((kuro--initialized t)
        (kuro--session-id 55)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-image)
               (lambda (sid _image-id) (setq captured-sid sid) nil)))
      (kuro--get-image 1)
      (should (= captured-sid 55)))))

(ert-deftest kuro-ffi-osc-get-palette-updates-forwards-session-id ()
  "kuro--get-palette-updates passes kuro--session-id to kuro-core-get-palette-updates."
  (let ((kuro--initialized t)
        (kuro--session-id 66)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-palette-updates)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--get-palette-updates)
      (should (= captured-sid 66)))))

(ert-deftest kuro-ffi-osc-get-default-colors-forwards-session-id ()
  "kuro--get-default-colors passes kuro--session-id to kuro-core-get-default-colors."
  (let ((kuro--initialized t)
        (kuro--session-id 77)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-default-colors)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--get-default-colors)
      (should (= captured-sid 77)))))

(ert-deftest kuro-ffi-osc-clear-scrollback-forwards-session-id ()
  "kuro--clear-scrollback passes kuro--session-id to kuro-core-clear-scrollback."
  (let ((kuro--initialized t)
        (kuro--session-id 88)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-clear-scrollback)
               (lambda (sid) (setq captured-sid sid) t)))
      (kuro--clear-scrollback)
      (should (= captured-sid 88)))))

;;; Group 5: Zero-vs-nil distinction and edge cases
;;
;; kuro--get-scrollback-count has fallback nil (not 0) but the core may
;; legitimately return 0 when the buffer is empty.  Tests distinguish these
;; two zero-like outcomes.

(ert-deftest kuro-ffi-osc-get-scrollback-count-returns-zero-when-buffer-empty ()
  "kuro--get-scrollback-count returns 0 (not nil) when core returns 0."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback-count)
               (lambda (_id) 0)))
      (should (= 0 (kuro--get-scrollback-count))))))

(ert-deftest kuro-ffi-osc-get-scrollback-count-nil-not-zero-when-uninit ()
  "kuro--get-scrollback-count returns nil (not 0) when kuro--initialized is nil.
The fallback is nil, and kuro--call uses `when', so nil is always returned
when uninitialized — even though 0 would be a valid initialized result."
  (let ((kuro--initialized nil))
    (should (null (kuro--get-scrollback-count)))))

(ert-deftest kuro-ffi-osc-get-image-id-zero-passed-to-core ()
  "kuro--get-image correctly forwards image-id 0 (not treated as falsy)."
  (let ((kuro--initialized t)
        (received-id :not-set))
    (cl-letf (((symbol-function 'kuro-core-get-image)
               (lambda (_sid id) (setq received-id id) nil)))
      (kuro--get-image 0)
      (should (= received-id 0)))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-returns-fallback-zero-on-ffi-error ()
  "kuro--get-scroll-offset returns 0 (the declared fallback) when core errors."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scroll-offset)
               (lambda (_id) (error "scroll error"))))
      (should (= 0 (kuro--get-scroll-offset))))))

;;; Group 6: session-id forwarding for remaining wrappers
;;
;; Groups 3-4 covered scroll-up/down, get-scrollback, and a selection of OSC
;; getters.  This group fills in the remaining wrappers so every function in
;; kuro-ffi-osc.el has at least one session-id forwarding test.

(ert-deftest kuro-ffi-osc-get-scrollback-count-forwards-session-id ()
  "kuro--get-scrollback-count passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 101)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback-count)
               (lambda (sid) (setq captured-sid sid) 5)))
      (kuro--get-scrollback-count)
      (should (= captured-sid 101)))))

(ert-deftest kuro-ffi-osc-set-scrollback-max-lines-forwards-session-id ()
  "kuro--set-scrollback-max-lines passes kuro--session-id as first arg."
  (let ((kuro--initialized t)
        (kuro--session-id 102)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-set-scrollback-max-lines)
               (lambda (sid _n) (setq captured-sid sid) t)))
      (kuro--set-scrollback-max-lines 500)
      (should (= captured-sid 102)))))

(ert-deftest kuro-ffi-osc-has-pending-output-forwards-session-id ()
  "kuro--has-pending-output passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 103)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-has-pending-output)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--has-pending-output)
      (should (= captured-sid 103)))))

(ert-deftest kuro-ffi-osc-poll-image-notifications-forwards-session-id ()
  "kuro--poll-image-notifications passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 104)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-poll-image-notifications)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--poll-image-notifications)
      (should (= captured-sid 104)))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-forwards-session-id ()
  "kuro--consume-scroll-events passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 105)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--consume-scroll-events)
      (should (= captured-sid 105)))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-forwards-session-id ()
  "kuro--get-scroll-offset passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 106)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-scroll-offset)
               (lambda (sid) (setq captured-sid sid) 0)))
      (kuro--get-scroll-offset)
      (should (= captured-sid 106)))))

(ert-deftest kuro-ffi-osc-get-image-forwards-image-id-large ()
  "kuro--get-image forwards large image-id values (e.g. u32 max boundary)."
  (let ((kuro--initialized t)
        (received-id nil))
    (cl-letf (((symbol-function 'kuro-core-get-image)
               (lambda (_sid id) (setq received-id id) nil)))
      (kuro--get-image 4294967295)
      (should (= received-id 4294967295)))))

;;; Group 7: value semantics, multi-entry results, and edge cases
;;
;; Tests for exact shapes of multi-entry payloads, boundary argument values,
;; and the clear-then-nil idempotency of consume-style functions.

(ert-deftest kuro-ffi-osc-get-and-clear-title-returns-string ()
  "kuro--get-and-clear-title returns the exact string provided by the core."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-and-clear-title)
               (lambda (_id) "My Terminal")))
      (should (equal "My Terminal" (kuro--get-and-clear-title))))))

(ert-deftest kuro-ffi-osc-get-and-clear-title-returns-nil-when-not-dirty ()
  "kuro--get-and-clear-title returns nil when core signals title is clean."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-and-clear-title)
               (lambda (_id) nil)))
      (should (null (kuro--get-and-clear-title))))))

(ert-deftest kuro-ffi-osc-get-cwd-returns-path-string ()
  "kuro--get-cwd returns the exact path string provided by the core."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-cwd)
               (lambda (_id) "/home/user/project")))
      (should (equal "/home/user/project" (kuro--get-cwd))))))

(ert-deftest kuro-ffi-osc-poll-clipboard-actions-multiple-entries ()
  "kuro--poll-clipboard-actions passes through a list with multiple action pairs."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-clipboard-actions)
               (lambda (_id) '((write . "text1") (query . nil) (write . "text2")))))
      (let ((result (kuro--poll-clipboard-actions)))
        (should (= (length result) 3))
        (should (eq (car (nth 0 result)) 'write))
        (should (eq (car (nth 1 result)) 'query))
        (should (null (cdr (nth 1 result))))
        (should (equal (cdr (nth 2 result)) "text2"))))))

(ert-deftest kuro-ffi-osc-poll-prompt-marks-all-mark-types ()
  "kuro--poll-prompt-marks passes through all four mark type symbols."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-prompt-marks)
               (lambda (_id)
                 '((0 . prompt-start)
                   (5 . prompt-end)
                   (6 . command-start)
                   (10 . command-end)))))
      (let ((result (kuro--poll-prompt-marks)))
        (should (= (length result) 4))
        (should (eq (cdr (nth 0 result)) 'prompt-start))
        (should (eq (cdr (nth 1 result)) 'prompt-end))
        (should (eq (cdr (nth 2 result)) 'command-start))
        (should (eq (cdr (nth 3 result)) 'command-end))))))

(ert-deftest kuro-ffi-osc-get-palette-updates-multi-entry-list ()
  "kuro--get-palette-updates passes through a list of multiple palette entries."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-palette-updates)
               (lambda (_id) '((0 0 0 0) (1 255 0 0) (15 255 255 255)))))
      (let ((result (kuro--get-palette-updates)))
        (should (= (length result) 3))
        (should (equal (nth 0 result) '(0 0 0 0)))
        (should (equal (nth 1 result) '(1 255 0 0)))
        (should (equal (nth 2 result) '(15 255 255 255)))))))

(ert-deftest kuro-ffi-osc-get-default-colors-field-layout ()
  "kuro--get-default-colors returns (FG-ENC BG-ENC CURSOR-ENC) in that order."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-default-colors)
               (lambda (_id) '(#x00FFFFFF #x00000000 #x00AAAAAA))))
      (let ((result (kuro--get-default-colors)))
        (should (= (nth 0 result) #x00FFFFFF))   ; fg
        (should (= (nth 1 result) #x00000000))   ; bg
        (should (= (nth 2 result) #x00AAAAAA)))))) ; cursor

(ert-deftest kuro-ffi-osc-get-default-colors-use-default-sentinel ()
  "kuro--get-default-colors returns #xFF000000 sentinel for use-default colors."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-default-colors)
               (lambda (_id) (list #xFF000000 #xFF000000 #xFF000000))))
      (let ((result (kuro--get-default-colors)))
        (should (= (nth 0 result) #xFF000000))
        (should (= (nth 1 result) #xFF000000))
        (should (= (nth 2 result) #xFF000000))))))

(ert-deftest kuro-ffi-osc-get-scrollback-max-lines-zero ()
  "kuro--get-scrollback with max-lines=0 forwards 0 to the core function."
  (let ((kuro--initialized t)
        (captured-max :not-set))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback)
               (lambda (_id n) (setq captured-max n) nil)))
      (kuro--get-scrollback 0)
      (should (= captured-max 0)))))

(ert-deftest kuro-ffi-osc-scroll-up-zero-lines ()
  "kuro--scroll-up with n=0 forwards 0 to the core (boundary, not filtered)."
  (let ((kuro--initialized t)
        (received-n :not-set))
    (cl-letf (((symbol-function 'kuro-core-scroll-up)
               (lambda (_id n) (setq received-n n) nil)))
      (kuro--scroll-up 0)
      (should (= received-n 0)))))

(ert-deftest kuro-ffi-osc-scroll-down-zero-lines ()
  "kuro--scroll-down with n=0 forwards 0 to the core (boundary, not filtered)."
  (let ((kuro--initialized t)
        (received-n :not-set))
    (cl-letf (((symbol-function 'kuro-core-scroll-down)
               (lambda (_id n) (setq received-n n) nil)))
      (kuro--scroll-down 0)
      (should (= received-n 0)))))

(ert-deftest kuro-ffi-osc-get-scrollback-count-large-value ()
  "kuro--get-scrollback-count passes through large line counts verbatim."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback-count)
               (lambda (_id) 100000)))
      (should (= 100000 (kuro--get-scrollback-count))))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-both-directions ()
  "kuro--consume-scroll-events returns (UP . DOWN) when both directions occurred."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda (_id) '(4 . 7))))
      (let ((result (kuro--consume-scroll-events)))
        (should (= (car result) 4))
        (should (= (cdr result) 7))))))

(provide 'kuro-ffi-osc-test)

;;; kuro-ffi-osc-test.el ends here
