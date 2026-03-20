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
  (fset 'kuro-core-get-and-clear-title (lambda () nil)))
(unless (fboundp 'kuro-core-get-cwd)
  (fset 'kuro-core-get-cwd (lambda () nil)))
(unless (fboundp 'kuro-core-poll-clipboard-actions)
  (fset 'kuro-core-poll-clipboard-actions (lambda () nil)))
(unless (fboundp 'kuro-core-poll-prompt-marks)
  (fset 'kuro-core-poll-prompt-marks (lambda () nil)))
(unless (fboundp 'kuro-core-get-image)
  (fset 'kuro-core-get-image (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-image-notifications)
  (fset 'kuro-core-poll-image-notifications (lambda () nil)))
(unless (fboundp 'kuro-core-consume-scroll-events)
  (fset 'kuro-core-consume-scroll-events (lambda () nil)))
(unless (fboundp 'kuro-core-has-pending-output)
  (fset 'kuro-core-has-pending-output (lambda () nil)))
(unless (fboundp 'kuro-core-get-palette-updates)
  (fset 'kuro-core-get-palette-updates (lambda () nil)))
(unless (fboundp 'kuro-core-get-default-colors)
  (fset 'kuro-core-get-default-colors (lambda () nil)))
(unless (fboundp 'kuro-core-get-scrollback)
  (fset 'kuro-core-get-scrollback (lambda (_n) nil)))
(unless (fboundp 'kuro-core-clear-scrollback)
  (fset 'kuro-core-clear-scrollback (lambda () nil)))
(unless (fboundp 'kuro-core-set-scrollback-max-lines)
  (fset 'kuro-core-set-scrollback-max-lines (lambda (_n) nil)))
(unless (fboundp 'kuro-core-get-scrollback-count)
  (fset 'kuro-core-get-scrollback-count (lambda () 0)))
(unless (fboundp 'kuro-core-scroll-up)
  (fset 'kuro-core-scroll-up (lambda (_n) nil)))
(unless (fboundp 'kuro-core-scroll-down)
  (fset 'kuro-core-scroll-down (lambda (_n) nil)))
(unless (fboundp 'kuro-core-get-scroll-offset)
  (fset 'kuro-core-get-scroll-offset (lambda () 0)))

;; Also stub kuro-core-init and other functions required transitively.
(unless (fboundp 'kuro-core-init)
  (fset 'kuro-core-init (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-resize)
  (fset 'kuro-core-resize (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-send-key)
  (fset 'kuro-core-send-key (lambda (&rest _) nil)))
(unless (fboundp 'kuro-core-poll-updates)
  (fset 'kuro-core-poll-updates (lambda () nil)))
(unless (fboundp 'kuro-core-poll-updates-with-faces)
  (fset 'kuro-core-poll-updates-with-faces (lambda () nil)))
(unless (fboundp 'kuro-core-get-cursor)
  (fset 'kuro-core-get-cursor (lambda () nil)))
(unless (fboundp 'kuro-core-is-cursor-visible)
  (fset 'kuro-core-is-cursor-visible (lambda () t)))
(unless (fboundp 'kuro-core-get-cursor-shape)
  (fset 'kuro-core-get-cursor-shape (lambda () 0)))
(unless (fboundp 'kuro-core-get-mouse-tracking-mode)
  (fset 'kuro-core-get-mouse-tracking-mode (lambda () nil)))
(unless (fboundp 'kuro-core-get-bracketed-paste)
  (fset 'kuro-core-get-bracketed-paste (lambda () nil)))
(unless (fboundp 'kuro-core-is-alt-screen-active)
  (fset 'kuro-core-is-alt-screen-active (lambda () nil)))
(unless (fboundp 'kuro-core-get-focus-tracking)
  (fset 'kuro-core-get-focus-tracking (lambda () nil)))
(unless (fboundp 'kuro-core-get-kitty-kb-flags)
  (fset 'kuro-core-get-kitty-kb-flags (lambda () 0)))
(unless (fboundp 'kuro-core-get-sync-update-active)
  (fset 'kuro-core-get-sync-update-active (lambda () nil)))
(unless (fboundp 'kuro-core-shutdown)
  (fset 'kuro-core-shutdown (lambda () nil)))

;; Stub kuro-ffi-modes functions required transitively by kuro-navigation.el.
(unless (fboundp 'kuro-core-get-app-cursor-keys)
  (fset 'kuro-core-get-app-cursor-keys (lambda () nil)))
(unless (fboundp 'kuro-core-get-focus-events)
  (fset 'kuro-core-get-focus-events (lambda () nil)))

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
               (lambda () (setq called t) "test-title")))
      (let ((result (kuro--get-and-clear-title)))
        (should called)
        (should (equal result "test-title"))))))

(ert-deftest kuro-ffi-osc-get-cwd-calls-core-when-init ()
  "kuro--get-cwd calls kuro-core-get-cwd when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-cwd)
               (lambda () (setq called t) "/home/user")))
      (let ((result (kuro--get-cwd)))
        (should called)
        (should (equal result "/home/user"))))))

(ert-deftest kuro-ffi-osc-poll-clipboard-actions-calls-core-when-init ()
  "kuro--poll-clipboard-actions calls kuro-core-poll-clipboard-actions when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-poll-clipboard-actions)
               (lambda () (setq called t) '((write . "hello")))))
      (let ((result (kuro--poll-clipboard-actions)))
        (should called)
        (should (equal result '((write . "hello"))))))))

(ert-deftest kuro-ffi-osc-poll-prompt-marks-calls-core-when-init ()
  "kuro--poll-prompt-marks calls kuro-core-poll-prompt-marks when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-poll-prompt-marks)
               (lambda () (setq called t) '((0 . prompt-start)))))
      (let ((result (kuro--poll-prompt-marks)))
        (should called)
        (should (equal result '((0 . prompt-start))))))))

(ert-deftest kuro-ffi-osc-get-image-calls-core-when-init ()
  "kuro--get-image calls kuro-core-get-image with the image-id argument."
  (let ((kuro--initialized t)
        (received-id nil))
    (cl-letf (((symbol-function 'kuro-core-get-image)
               (lambda (id) (setq received-id id) "base64data")))
      (let ((result (kuro--get-image 42)))
        (should (= received-id 42))
        (should (equal result "base64data"))))))

(ert-deftest kuro-ffi-osc-poll-image-notifications-calls-core-when-init ()
  "kuro--poll-image-notifications calls kuro-core-poll-image-notifications when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-poll-image-notifications)
               (lambda () (setq called t) '((1 0 0 10 5)))))
      (let ((result (kuro--poll-image-notifications)))
        (should called)
        (should (equal result '((1 0 0 10 5))))))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-calls-core-when-init ()
  "kuro--consume-scroll-events calls kuro-core-consume-scroll-events when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda () (setq called t) '(2 . 0))))
      (let ((result (kuro--consume-scroll-events)))
        (should called)
        (should (equal result '(2 . 0)))))))

(ert-deftest kuro-ffi-osc-has-pending-output-calls-core-when-init ()
  "kuro--has-pending-output calls kuro-core-has-pending-output when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-has-pending-output)
               (lambda () (setq called t) t)))
      (let ((result (kuro--has-pending-output)))
        (should called)
        (should result)))))

(ert-deftest kuro-ffi-osc-get-palette-updates-calls-core-when-init ()
  "kuro--get-palette-updates calls kuro-core-get-palette-updates when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-palette-updates)
               (lambda () (setq called t) '((1 255 0 0)))))
      (let ((result (kuro--get-palette-updates)))
        (should called)
        (should (equal result '((1 255 0 0))))))))

(ert-deftest kuro-ffi-osc-get-default-colors-calls-core-when-init ()
  "kuro--get-default-colors calls kuro-core-get-default-colors when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-default-colors)
               (lambda () (setq called t) '(#xFFFFFF #x000000 #xAAAAAA))))
      (let ((result (kuro--get-default-colors)))
        (should called)
        (should (equal result '(#xFFFFFF #x000000 #xAAAAAA)))))))

(ert-deftest kuro-ffi-osc-get-scrollback-calls-core-when-init ()
  "kuro--get-scrollback calls kuro-core-get-scrollback with max-lines argument."
  (let ((kuro--initialized t)
        (received-max nil))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback)
               (lambda (n) (setq received-max n) '("line1" "line2"))))
      (let ((result (kuro--get-scrollback 100)))
        (should (= received-max 100))
        (should (equal result '("line1" "line2")))))))

(ert-deftest kuro-ffi-osc-clear-scrollback-calls-core-when-init ()
  "kuro--clear-scrollback calls kuro-core-clear-scrollback when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-clear-scrollback)
               (lambda () (setq called t) t)))
      (let ((result (kuro--clear-scrollback)))
        (should called)
        (should result)))))

(ert-deftest kuro-ffi-osc-set-scrollback-max-lines-calls-core-when-init ()
  "kuro--set-scrollback-max-lines calls kuro-core-set-scrollback-max-lines with argument."
  (let ((kuro--initialized t)
        (received-n nil))
    (cl-letf (((symbol-function 'kuro-core-set-scrollback-max-lines)
               (lambda (n) (setq received-n n) t)))
      (let ((result (kuro--set-scrollback-max-lines 1000)))
        (should (= received-n 1000))
        (should result)))))

(ert-deftest kuro-ffi-osc-get-scrollback-count-calls-core-when-init ()
  "kuro--get-scrollback-count calls kuro-core-get-scrollback-count when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback-count)
               (lambda () (setq called t) 42)))
      (let ((result (kuro--get-scrollback-count)))
        (should called)
        (should (= result 42))))))

(ert-deftest kuro-ffi-osc-scroll-up-calls-core-when-init ()
  "kuro--scroll-up calls kuro-core-scroll-up with the n argument."
  (let ((kuro--initialized t)
        (received-n nil))
    (cl-letf (((symbol-function 'kuro-core-scroll-up)
               (lambda (n) (setq received-n n) t)))
      (kuro--scroll-up 3)
      (should (= received-n 3)))))

(ert-deftest kuro-ffi-osc-scroll-down-calls-core-when-init ()
  "kuro--scroll-down calls kuro-core-scroll-down with the n argument."
  (let ((kuro--initialized t)
        (received-n nil))
    (cl-letf (((symbol-function 'kuro-core-scroll-down)
               (lambda (n) (setq received-n n) t)))
      (kuro--scroll-down 5)
      (should (= received-n 5)))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-calls-core-when-init ()
  "kuro--get-scroll-offset calls kuro-core-get-scroll-offset when initialized."
  (let ((kuro--initialized t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-get-scroll-offset)
               (lambda () (setq called t) 7)))
      (let ((result (kuro--get-scroll-offset)))
        (should called)
        (should (= result 7))))))

(provide 'kuro-ffi-osc-test)

;;; kuro-ffi-osc-test.el ends here
