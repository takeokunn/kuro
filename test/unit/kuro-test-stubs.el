;;; kuro-test-stubs.el --- Canonical Rust FFI stubs for all unit tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Single source of truth for Rust FFI symbol stubs used across all unit tests.
;; Every symbol the Rust .so would provide is defined here as a no-op lambda
;; (or with a minimal return value where non-nil is required).
;;
;; Use `(require 'kuro-test-stubs)' before any kuro require in test files.
;; The `unless (fboundp ...)' guard ensures a real loaded module is not
;; overridden if this file is loaded in a session where the module is present.

;;; Code:

(require 'cl-lib)

;;; ── Nil-returning stubs ──────────────────────────────────────────────────────

(dolist (sym '(kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-and-clear-title
               kuro-core-get-default-colors
               kuro-core-get-palette-updates
               kuro-core-get-image
               kuro-core-take-bell-pending
               kuro-core-get-focus-events
               kuro-core-get-app-cursor-keys
               kuro-core-get-app-keypad
               kuro-core-get-bracketed-paste
               kuro-core-get-mouse-mode
               kuro-core-get-mouse-sgr
               kuro-core-get-mouse-pixel
               kuro-core-get-keyboard-flags
               kuro-core-get-scrollback
               kuro-core-get-sync-output
               kuro-core-get-cwd
               kuro-core-has-pending-output
               kuro-core-is-process-alive
               kuro-core-poll-clipboard-actions
               kuro-core-poll-image-notifications
               kuro-core-poll-prompt-marks
               kuro-core-scroll-up
               kuro-core-scroll-down
               kuro-core-consume-scroll-events
               kuro-core-clear-scrollback
               kuro-core-set-scrollback-max-lines
               kuro-core-detach
               kuro-core-attach
               kuro-core-list-sessions
               kuro-core-poll-eval-commands
               kuro-core-get-cwd-host
               kuro-core-get-mouse-tracking-mode
               kuro-core-is-alt-screen-active
               kuro-core-get-focus-tracking
               kuro-core-get-sync-update-active
               kuro-core-get-cursor-visible))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

;;; ── Non-nil stubs (specific return values required) ─────────────────────────

(unless (fboundp 'kuro-core-init)
  (fset 'kuro-core-init (lambda (&rest _) t)))

(unless (fboundp 'kuro-core-resize)
  (fset 'kuro-core-resize (lambda (&rest _) t)))

(unless (fboundp 'kuro-core-is-cursor-visible)
  (fset 'kuro-core-is-cursor-visible (lambda (_id) t)))

(unless (fboundp 'kuro-core-get-cursor-shape)
  (fset 'kuro-core-get-cursor-shape (lambda (_id) 0)))

(unless (fboundp 'kuro-core-get-kitty-kb-flags)
  (fset 'kuro-core-get-kitty-kb-flags (lambda (_id) 0)))

(unless (fboundp 'kuro-core-get-scroll-offset)
  (fset 'kuro-core-get-scroll-offset (lambda (_id) 0)))

(unless (fboundp 'kuro-core-get-scrollback-count)
  (fset 'kuro-core-get-scrollback-count (lambda (_id) 0)))

;;; ── module-load stub ─────────────────────────────────────────────────────────

;; Stub module-load so kuro-module-load silently succeeds without a .so/.dylib.
(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(provide 'kuro-test-stubs)

;;; kuro-test-stubs.el ends here
