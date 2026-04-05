;;; kuro-eval-test.el --- Unit tests for kuro-eval.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-eval.el (OSC 51 eval whitelist).
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

(require 'kuro-eval)

;;; Group 1: kuro--eval-command-allowed-p whitelist filtering

(ert-deftest kuro-eval-allowed-cd-bare ()
  "kuro--eval-command-allowed-p returns non-nil for bare \"cd /tmp\"."
  (should (kuro--eval-command-allowed-p "cd /tmp")))

(ert-deftest kuro-eval-allowed-cd-sexp ()
  "kuro--eval-command-allowed-p returns non-nil for sexp (cd \"/tmp\")."
  (should (kuro--eval-command-allowed-p "(cd \"/tmp\")")))

(ert-deftest kuro-eval-allowed-setenv ()
  "kuro--eval-command-allowed-p returns non-nil for setenv command."
  (should (kuro--eval-command-allowed-p "(setenv \"FOO\" \"bar\")")))

(ert-deftest kuro-eval-allowed-kuro-prefix ()
  "kuro--eval-command-allowed-p returns non-nil for kuro- prefixed commands."
  (should (kuro--eval-command-allowed-p "(kuro-create)")))

(ert-deftest kuro-eval-blocked-delete-file ()
  "kuro--eval-command-allowed-p returns nil for delete-file."
  (should-not (kuro--eval-command-allowed-p "(delete-file \"/etc/passwd\")")))

(ert-deftest kuro-eval-blocked-eval ()
  "kuro--eval-command-allowed-p returns nil for eval command."
  (should-not (kuro--eval-command-allowed-p "(eval (something))")))

(ert-deftest kuro-eval-blocked-empty ()
  "kuro--eval-command-allowed-p returns nil for empty string."
  (should-not (kuro--eval-command-allowed-p "")))

(ert-deftest kuro-eval-blocked-whitespace-only ()
  "kuro--eval-command-allowed-p returns nil for whitespace-only string."
  (should-not (kuro--eval-command-allowed-p "   ")))

;;; Group 2: kuro--eval-osc51-command evaluation

(ert-deftest kuro-eval-osc51-evaluates-whitelisted ()
  "kuro--eval-osc51-command evaluates whitelisted setenv sexp."
  (let ((var-name "KURO_TEST_OSC51_VAR"))
    (unwind-protect
        (progn
          (kuro--eval-osc51-command (format "(setenv \"%s\" \"hello\")" var-name))
          (should (string= (getenv var-name) "hello")))
      (setenv var-name nil))))

(ert-deftest kuro-eval-osc51-returns-nil-for-blocked ()
  "kuro--eval-osc51-command returns nil for blocked command."
  (should-not (kuro--eval-osc51-command "(delete-file \"/etc/passwd\")")))

(ert-deftest kuro-eval-osc51-handles-eval-error ()
  "kuro--eval-osc51-command handles eval errors gracefully."
  ;; A whitelisted command that triggers an error should return nil, not signal.
  (should-not (kuro--eval-osc51-command "(setenv)")))

;;; Group 3: defcustom defaults

(ert-deftest kuro-eval-whitelist-default-entries ()
  "kuro-eval-command-whitelist default has cd, setenv, and kuro- entries."
  (should (member "cd" kuro-eval-command-whitelist))
  (should (member "setenv" kuro-eval-command-whitelist))
  (should (member "kuro-" kuro-eval-command-whitelist)))

;;; Group 4: kuro--poll-eval-command-updates integration

(ert-deftest kuro-eval-poll-processes-commands ()
  "kuro--poll-eval-command-updates processes commands from the FFI."
  (let ((kuro--initialized t)
        (processed nil))
    (cl-letf (((symbol-function 'kuro-core-poll-eval-commands)
               (lambda (_id) '("(cd \"/tmp\")")))
              ((symbol-function 'kuro--eval-osc51-command)
               (lambda (cmd) (push cmd processed) nil)))
      (kuro--poll-eval-command-updates)
      (should (equal processed '("(cd \"/tmp\")"))))))

(provide 'kuro-eval-test)

;;; kuro-eval-test.el ends here
