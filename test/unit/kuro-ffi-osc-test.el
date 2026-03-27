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

;;; Group 1: kuro--initialized=nil guard path
;;
;; When `kuro--initialized' is nil, the `kuro--call' macro expands to
;; (when nil ...) which short-circuits and returns nil unconditionally —
;; regardless of the declared fallback value.  Every wrapper must honour this.

(ert-deftest kuro-ffi-osc-get-and-clear-title-nil-when-uninit ()
  "kuro--get-and-clear-title returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-and-clear-title))))

(ert-deftest kuro-ffi-osc-get-cwd-nil-when-uninit ()
  "kuro--get-cwd returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-cwd))))

(ert-deftest kuro-ffi-osc-poll-clipboard-actions-nil-when-uninit ()
  "kuro--poll-clipboard-actions returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--poll-clipboard-actions))))

(ert-deftest kuro-ffi-osc-poll-prompt-marks-nil-when-uninit ()
  "kuro--poll-prompt-marks returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--poll-prompt-marks))))

(ert-deftest kuro-ffi-osc-get-image-nil-when-uninit ()
  "kuro--get-image returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-image 0))))

(ert-deftest kuro-ffi-osc-poll-image-notifications-nil-when-uninit ()
  "kuro--poll-image-notifications returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--poll-image-notifications))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-nil-when-uninit ()
  "kuro--consume-scroll-events returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--consume-scroll-events))))

(ert-deftest kuro-ffi-osc-has-pending-output-nil-when-uninit ()
  "kuro--has-pending-output returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--has-pending-output))))

(ert-deftest kuro-ffi-osc-get-palette-updates-nil-when-uninit ()
  "kuro--get-palette-updates returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-palette-updates))))

(ert-deftest kuro-ffi-osc-get-default-colors-nil-when-uninit ()
  "kuro--get-default-colors returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-default-colors))))

(ert-deftest kuro-ffi-osc-get-scrollback-nil-when-uninit ()
  "kuro--get-scrollback returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-scrollback 100))))

(ert-deftest kuro-ffi-osc-clear-scrollback-nil-when-uninit ()
  "kuro--clear-scrollback returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--clear-scrollback))))

(ert-deftest kuro-ffi-osc-set-scrollback-max-lines-nil-when-uninit ()
  "kuro--set-scrollback-max-lines returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--set-scrollback-max-lines 1000))))

(ert-deftest kuro-ffi-osc-get-scrollback-count-nil-when-uninit ()
  "kuro--get-scrollback-count returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-scrollback-count))))

(ert-deftest kuro-ffi-osc-scroll-up-nil-when-uninit ()
  "kuro--scroll-up returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--scroll-up 1))))

(ert-deftest kuro-ffi-osc-scroll-down-nil-when-uninit ()
  "kuro--scroll-down returns nil when kuro--initialized is nil."
  (let ((kuro--initialized nil))
    (should-not (kuro--scroll-down 1))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-nil-when-uninit ()
  "kuro--get-scroll-offset returns nil when kuro--initialized is nil.
Note: fallback is 0 but kuro--call uses `when', so nil is returned when uninit."
  (let ((kuro--initialized nil))
    (should-not (kuro--get-scroll-offset))))

;;; Group 2: kuro--initialized=t calls the underlying core function
;;
;; Each wrapper must delegate to its kuro-core-* counterpart when initialized.
;; cl-letf stubs the core function; tests verify both that the stub was called
;; and that the return value is passed through unchanged.

(ert-deftest kuro-ffi-osc-get-and-clear-title-calls-core-when-init ()
  "kuro--get-and-clear-title calls kuro-core-get-and-clear-title when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-and-clear-title)
               (lambda (_id) (setq called t) "test-title")))
      (let ((result (kuro--get-and-clear-title)))
        (should called)
        (should (equal result "test-title"))))))

(ert-deftest kuro-ffi-osc-get-cwd-calls-core-when-init ()
  "kuro--get-cwd calls kuro-core-get-cwd when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-cwd)
               (lambda (_id) (setq called t) "/home/user")))
      (let ((result (kuro--get-cwd)))
        (should called)
        (should (equal result "/home/user"))))))

(ert-deftest kuro-ffi-osc-poll-clipboard-actions-calls-core-when-init ()
  "kuro--poll-clipboard-actions calls kuro-core-poll-clipboard-actions when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-poll-clipboard-actions)
               (lambda (_id) (setq called t) '((write . "hello")))))
      (let ((result (kuro--poll-clipboard-actions)))
        (should called)
        (should (equal result '((write . "hello"))))))))

(ert-deftest kuro-ffi-osc-poll-prompt-marks-calls-core-when-init ()
  "kuro--poll-prompt-marks calls kuro-core-poll-prompt-marks when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-poll-prompt-marks)
               (lambda (_id) (setq called t) '((0 . prompt-start)))))
      (let ((result (kuro--poll-prompt-marks)))
        (should called)
        (should (equal result '((0 . prompt-start))))))))

(ert-deftest kuro-ffi-osc-get-image-calls-core-when-init ()
  "kuro--get-image calls kuro-core-get-image with the image-id argument."
  (let ((kuro--initialized t)
        (received-id nil))
    (cl-letf (((symbol-function 'kuro-core-get-image)
               (lambda (_id id) (setq received-id id) "base64data")))
      (let ((result (kuro--get-image 42)))
        (should (= received-id 42))
        (should (equal result "base64data"))))))

(ert-deftest kuro-ffi-osc-poll-image-notifications-calls-core-when-init ()
  "kuro--poll-image-notifications calls kuro-core-poll-image-notifications when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-poll-image-notifications)
               (lambda (_id) (setq called t) '((1 0 0 10 5)))))
      (let ((result (kuro--poll-image-notifications)))
        (should called)
        (should (equal result '((1 0 0 10 5))))))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-calls-core-when-init ()
  "kuro--consume-scroll-events calls kuro-core-consume-scroll-events when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda (_id) (setq called t) '(2 . 0))))
      (let ((result (kuro--consume-scroll-events)))
        (should called)
        (should (equal result '(2 . 0)))))))

(ert-deftest kuro-ffi-osc-has-pending-output-calls-core-when-init ()
  "kuro--has-pending-output calls kuro-core-has-pending-output when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-has-pending-output)
               (lambda (_id) (setq called t) t)))
      (let ((result (kuro--has-pending-output)))
        (should called)
        (should result)))))

(ert-deftest kuro-ffi-osc-get-palette-updates-calls-core-when-init ()
  "kuro--get-palette-updates calls kuro-core-get-palette-updates when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-palette-updates)
               (lambda (_id) (setq called t) '((1 255 0 0)))))
      (let ((result (kuro--get-palette-updates)))
        (should called)
        (should (equal result '((1 255 0 0))))))))

(ert-deftest kuro-ffi-osc-get-default-colors-calls-core-when-init ()
  "kuro--get-default-colors calls kuro-core-get-default-colors when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-default-colors)
               (lambda (_id) (setq called t) '(#xFFFFFF #x000000 #xAAAAAA))))
      (let ((result (kuro--get-default-colors)))
        (should called)
        (should (equal result '(#xFFFFFF #x000000 #xAAAAAA)))))))

(ert-deftest kuro-ffi-osc-get-scrollback-calls-core-when-init ()
  "kuro--get-scrollback calls kuro-core-get-scrollback with max-lines argument."
  (let ((kuro--initialized t)
        (received-max nil))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback)
               (lambda (_id n) (setq received-max n) '("line1" "line2"))))
      (let ((result (kuro--get-scrollback 100)))
        (should (= received-max 100))
        (should (equal result '("line1" "line2")))))))

(ert-deftest kuro-ffi-osc-clear-scrollback-calls-core-when-init ()
  "kuro--clear-scrollback calls kuro-core-clear-scrollback when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-clear-scrollback)
               (lambda (_id) (setq called t) t)))
      (let ((result (kuro--clear-scrollback)))
        (should called)
        (should result)))))

(ert-deftest kuro-ffi-osc-set-scrollback-max-lines-calls-core-when-init ()
  "kuro--set-scrollback-max-lines calls kuro-core-set-scrollback-max-lines with argument."
  (let ((kuro--initialized t)
        (received-n nil))
    (cl-letf (((symbol-function 'kuro-core-set-scrollback-max-lines)
               (lambda (_id n) (setq received-n n) t)))
      (let ((result (kuro--set-scrollback-max-lines 1000)))
        (should (= received-n 1000))
        (should result)))))

(ert-deftest kuro-ffi-osc-get-scrollback-count-calls-core-when-init ()
  "kuro--get-scrollback-count calls kuro-core-get-scrollback-count when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback-count)
               (lambda (_id) (setq called t) 42)))
      (let ((result (kuro--get-scrollback-count)))
        (should called)
        (should (= result 42))))))

(ert-deftest kuro-ffi-osc-scroll-up-calls-core-when-init ()
  "kuro--scroll-up calls kuro-core-scroll-up with the n argument."
  (let ((kuro--initialized t)
        (received-n nil))
    (cl-letf (((symbol-function 'kuro-core-scroll-up)
               (lambda (_id n) (setq received-n n) t)))
      (kuro--scroll-up 3)
      (should (= received-n 3)))))

(ert-deftest kuro-ffi-osc-scroll-down-calls-core-when-init ()
  "kuro--scroll-down calls kuro-core-scroll-down with the n argument."
  (let ((kuro--initialized t)
        (received-n nil))
    (cl-letf (((symbol-function 'kuro-core-scroll-down)
               (lambda (_id n) (setq received-n n) t)))
      (kuro--scroll-down 5)
      (should (= received-n 5)))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-calls-core-when-init ()
  "kuro--get-scroll-offset calls kuro-core-get-scroll-offset when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-scroll-offset)
               (lambda (_id) (setq called t) 7)))
      (let ((result (kuro--get-scroll-offset)))
        (should called)
        (should (= result 7))))))

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
