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

;; Stub the Rust FFI functions that kuro-ffi-osc.el's (require 'kuro-ffi) would need.
;; These must be defined BEFORE loading kuro-ffi-osc.el.
(unless (fboundp 'kuro-core-get-and-clear-title)
  (fset 'kuro-core-get-and-clear-title (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-cwd)
  (fset 'kuro-core-get-cwd (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-clipboard-actions)
  (fset 'kuro-core-poll-clipboard-actions (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-prompt-marks)
  (fset 'kuro-core-poll-prompt-marks (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-image)
  (fset 'kuro-core-get-image (lambda (_id _img-id) nil)))
(unless (fboundp 'kuro-core-poll-image-notifications)
  (fset 'kuro-core-poll-image-notifications (lambda (_id) nil)))
(unless (fboundp 'kuro-core-consume-scroll-events)
  (fset 'kuro-core-consume-scroll-events (lambda (_id) nil)))
(unless (fboundp 'kuro-core-has-pending-output)
  (fset 'kuro-core-has-pending-output (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-palette-updates)
  (fset 'kuro-core-get-palette-updates (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-default-colors)
  (fset 'kuro-core-get-default-colors (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-scrollback)
  (fset 'kuro-core-get-scrollback (lambda (_id _n) nil)))
(unless (fboundp 'kuro-core-clear-scrollback)
  (fset 'kuro-core-clear-scrollback (lambda (_id) nil)))
(unless (fboundp 'kuro-core-set-scrollback-max-lines)
  (fset 'kuro-core-set-scrollback-max-lines (lambda (_id _n) nil)))
(unless (fboundp 'kuro-core-get-scrollback-count)
  (fset 'kuro-core-get-scrollback-count (lambda (_id) 0)))
(unless (fboundp 'kuro-core-scroll-up)
  (fset 'kuro-core-scroll-up (lambda (_id _n) nil)))
(unless (fboundp 'kuro-core-scroll-down)
  (fset 'kuro-core-scroll-down (lambda (_id _n) nil)))
(unless (fboundp 'kuro-core-get-scroll-offset)
  (fset 'kuro-core-get-scroll-offset (lambda (_id) 0)))
(unless (fboundp 'kuro-core-poll-eval-commands)
  (fset 'kuro-core-poll-eval-commands (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-cwd-host)
  (fset 'kuro-core-get-cwd-host (lambda (_id) nil)))

;; Also stub kuro-core-init and other functions required transitively.
(unless (fboundp 'kuro-core-init)
  (fset 'kuro-core-init (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-resize)
  (fset 'kuro-core-resize (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-send-key)
  (fset 'kuro-core-send-key (lambda (&rest _) nil)))
(unless (fboundp 'kuro-core-poll-updates)
  (fset 'kuro-core-poll-updates (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-updates-with-faces)
  (fset 'kuro-core-poll-updates-with-faces (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-cursor)
  (fset 'kuro-core-get-cursor (lambda (_id) nil)))
(unless (fboundp 'kuro-core-is-cursor-visible)
  (fset 'kuro-core-is-cursor-visible (lambda (_id) t)))
(unless (fboundp 'kuro-core-get-cursor-shape)
  (fset 'kuro-core-get-cursor-shape (lambda (_id) 0)))
(unless (fboundp 'kuro-core-get-mouse-tracking-mode)
  (fset 'kuro-core-get-mouse-tracking-mode (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-bracketed-paste)
  (fset 'kuro-core-get-bracketed-paste (lambda (_id) nil)))
(unless (fboundp 'kuro-core-is-alt-screen-active)
  (fset 'kuro-core-is-alt-screen-active (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-focus-tracking)
  (fset 'kuro-core-get-focus-tracking (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-kitty-kb-flags)
  (fset 'kuro-core-get-kitty-kb-flags (lambda (_id) 0)))
(unless (fboundp 'kuro-core-get-sync-update-active)
  (fset 'kuro-core-get-sync-update-active (lambda (_id) nil)))
(unless (fboundp 'kuro-core-shutdown)
  (fset 'kuro-core-shutdown (lambda (_id) nil)))

;; Stub kuro-ffi-modes functions required transitively by kuro-navigation.el.
(unless (fboundp 'kuro-core-get-app-cursor-keys)
  (fset 'kuro-core-get-app-cursor-keys (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-focus-events)
  (fset 'kuro-core-get-focus-events (lambda (_id) nil)))

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

(provide 'kuro-ffi-osc-test)

;;; kuro-ffi-osc-test.el ends here
