;;; kuro-tramp-test.el --- Unit tests for kuro-tramp.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-tramp.el (Tramp integration for remote paths).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub the Rust FFI functions required transitively.
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
(unless (fboundp 'kuro-core-is-process-alive)
  (fset 'kuro-core-is-process-alive (lambda (_id) t)))
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
(unless (fboundp 'kuro-core-get-app-cursor-keys)
  (fset 'kuro-core-get-app-cursor-keys (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-focus-events)
  (fset 'kuro-core-get-focus-events (lambda (_id) nil)))

(defvar kuro--initialized nil)

(require 'kuro-tramp)

;;; Group 1: kuro--tramp-remote-path construction

(ert-deftest kuro-tramp-remote-path-default-method ()
  "kuro--tramp-remote-path constructs correct path with default ssh method."
  (let ((kuro-tramp-method "ssh"))
    (should (string= (kuro--tramp-remote-path "remote-host" "/home/user")
                      "/ssh:remote-host:/home/user"))))

(ert-deftest kuro-tramp-remote-path-host-and-path ()
  "kuro--tramp-remote-path uses host and path correctly."
  (let ((kuro-tramp-method "scp"))
    (should (string= (kuro--tramp-remote-path "server" "/var/log")
                      "/scp:server:/var/log"))))

(ert-deftest kuro-tramp-remote-path-nil-path ()
  "kuro--tramp-remote-path handles nil path by defaulting to /."
  (let ((kuro-tramp-method "ssh"))
    (should (string= (kuro--tramp-remote-path "host" nil)
                      "/ssh:host:/"))))

;;; Group 2: kuro--apply-cwd-with-tramp

(ert-deftest kuro-tramp-apply-cwd-local-when-host-nil ()
  "kuro--apply-cwd-with-tramp sets local path when host is nil."
  (let ((kuro--initialized t))
    (with-temp-buffer
      (cl-letf (((symbol-function 'kuro-core-get-cwd)
                 (lambda (_id) "/home/user"))
                ((symbol-function 'kuro-core-get-cwd-host)
                 (lambda (_id) nil)))
        (kuro--apply-cwd-with-tramp)
        (should (string= default-directory "/home/user/"))))))

(ert-deftest kuro-tramp-apply-cwd-tramp-when-host-present ()
  "kuro--apply-cwd-with-tramp sets tramp path when host is present."
  (let ((kuro--initialized t)
        (kuro-tramp-method "ssh"))
    (with-temp-buffer
      (cl-letf (((symbol-function 'kuro-core-get-cwd)
                 (lambda (_id) "/home/user"))
                ((symbol-function 'kuro-core-get-cwd-host)
                 (lambda (_id) "remote-box")))
        (kuro--apply-cwd-with-tramp)
        (should (string= default-directory "/ssh:remote-box:/home/user/"))))))

(ert-deftest kuro-tramp-apply-cwd-noop-when-cwd-nil ()
  "kuro--apply-cwd-with-tramp does nothing when cwd is nil."
  (let ((kuro--initialized t))
    (with-temp-buffer
      (let ((orig default-directory))
        (cl-letf (((symbol-function 'kuro-core-get-cwd)
                   (lambda (_id) nil)))
          (kuro--apply-cwd-with-tramp)
          (should (string= default-directory orig)))))))

;;; Group 3: defcustom defaults

(ert-deftest kuro-tramp-method-defaults-to-ssh ()
  "kuro-tramp-method defcustom defaults to \"ssh\"."
  (should (string= (default-value 'kuro-tramp-method) "ssh")))

(provide 'kuro-tramp-test)

;;; kuro-tramp-test.el ends here
