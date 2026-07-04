;;; kuro-eval-test.el --- Unit tests for kuro-eval.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-eval.el (OSC 51 command allowlist).
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

;;; Group 1: kuro--eval-command-allowed-p allowlist filtering

(ert-deftest kuro-eval-allowed-cd-bare ()
  "kuro--eval-command-allowed-p returns non-nil for bare \"cd /tmp\"."
  (should (kuro--eval-command-allowed-p "cd /tmp")))

(ert-deftest kuro-eval-rejects-cd-sexp ()
  "kuro--eval-command-allowed-p rejects legacy Elisp reader forms."
  (should-not (kuro--eval-command-allowed-p "(cd \"/tmp\")")))

(ert-deftest kuro-eval-allowed-setenv ()
  "kuro--eval-command-allowed-p returns non-nil for setenv command."
  (should (kuro--eval-command-allowed-p "setenv FOO bar")))

(ert-deftest kuro-eval-blocked-kuro-prefix ()
  "kuro--eval-command-allowed-p returns nil for kuro- prefixed commands."
  (should-not (kuro--eval-command-allowed-p "kuro-create")))

(ert-deftest kuro-eval-blocked-cd-prefix ()
  "kuro--eval-command-allowed-p returns nil for cd prefix matches."
  (should-not (kuro--eval-command-allowed-p "cd-evil /tmp")))

(ert-deftest kuro-eval-blocked-setenv-prefix ()
  "kuro--eval-command-allowed-p returns nil for setenv prefix matches."
  (should-not (kuro--eval-command-allowed-p "setenv-evil FOO bar")))

(ert-deftest kuro-eval-blocked-delete-file ()
  "kuro--eval-command-allowed-p returns nil for delete-file."
  (should-not (kuro--eval-command-allowed-p "delete-file /etc/passwd")))

(ert-deftest kuro-eval-blocked-eval ()
  "kuro--eval-command-allowed-p returns nil for the literal eval verb."
  (should-not (kuro--eval-command-allowed-p "eval something")))

(ert-deftest kuro-eval-blocked-empty ()
  "kuro--eval-command-allowed-p returns nil for empty string."
  (should-not (kuro--eval-command-allowed-p "")))

(ert-deftest kuro-eval-blocked-whitespace-only ()
  "kuro--eval-command-allowed-p returns nil for whitespace-only string."
  (should-not (kuro--eval-command-allowed-p "   ")))

(ert-deftest kuro-eval-blocked-non-string ()
  "kuro--eval-command-allowed-p returns nil for non-string commands."
  (should-not (kuro--eval-command-allowed-p 1)))

(ert-deftest kuro-eval-blocked-control-character ()
  "kuro--eval-command-allowed-p rejects control characters."
  (should-not (kuro--eval-command-allowed-p "setenv FOO hello\nworld")))

(ert-deftest kuro-eval-blocked-overlong-command ()
  "kuro--eval-command-allowed-p rejects oversized command payloads."
  (should-not
   (kuro--eval-command-allowed-p
    (concat "setenv FOO " (make-string kuro-eval--max-command-bytes ?a)))))

(ert-deftest kuro-eval-blocked-relative-cd ()
  "kuro--eval-command-allowed-p rejects relative cd targets."
  (let* ((root (make-temp-file "kuro-eval-root-" t))
         (child (expand-file-name "child" root)))
    (make-directory child)
    (unwind-protect
        (let ((default-directory root))
          (should-not (kuro--eval-command-allowed-p "cd child")))
      (delete-directory root t))))

(ert-deftest kuro-eval-blocked-nonexistent-cd ()
  "kuro--eval-command-allowed-p rejects nonexistent cd targets."
  (let ((missing (make-temp-file "kuro-eval-missing-" t)))
    (delete-directory missing t)
    (should-not (kuro--eval-command-allowed-p (format "cd %s" missing)))))

(ert-deftest kuro-eval-blocked-remote-cd ()
  "kuro--eval-command-allowed-p rejects remote cd targets."
  (should-not (kuro--eval-command-allowed-p "cd /ssh:example:/tmp")))

(ert-deftest kuro-eval-blocked-invalid-env-name ()
  "kuro--eval-command-allowed-p rejects non-strict environment names."
  (dolist (name '("1BAD" "BAD-NAME" "BAD.NAME" ""))
    (should-not
     (kuro--eval-command-allowed-p
      (format "setenv %s value" (shell-quote-argument name))))))

(ert-deftest kuro-eval-blocked-setenv-third-arg ()
  "kuro--eval-command-allowed-p rejects extra setenv arguments."
  (should-not (kuro--eval-command-allowed-p "setenv FOO bar extra")))

(ert-deftest kuro-eval-blocked-setenv-dangerous-names ()
  "kuro--eval-command-allowed-p rejects security-sensitive variable names.
Terminal output must not be able to hijack subprocesses Emacs later spawns."
  (dolist (name '("LD_PRELOAD" "LD_LIBRARY_PATH" "DYLD_INSERT_LIBRARIES"
                  "PATH" "SHELL" "IFS" "BASH_ENV" "PROMPT_COMMAND"
                  "GIT_SSH_COMMAND" "PYTHONPATH" "NODE_OPTIONS"
                  "BASH_FUNC_deploy"))
    (should-not
     (kuro--eval-command-allowed-p (format "setenv %s value" name)))))

(ert-deftest kuro-eval-blocked-setenv-dangerous-names-case-insensitive ()
  "The setenv denylist matches variable names case-insensitively."
  (should-not (kuro--eval-command-allowed-p "setenv ld_preload x"))
  (should-not (kuro--eval-command-allowed-p "setenv Path x")))

(ert-deftest kuro-eval-blocked-setenv-extended-injection-families ()
  "The denylist blocks env->RCE vectors beyond the linker/PATH families.
Each name is a documented code-execution primitive when a later Emacs
subprocess (git, less, python, ssh, ...) reads it."
  (dolist (name '(;; less input preprocessor: LESSOPEN=|cmd runs a shell.
                  "LESSOPEN" "LESSCLOSE" "LESS"
                  ;; git config injection (magit/vc spawn git constantly).
                  "GIT_CONFIG_COUNT" "GIT_CONFIG_KEY_0" "GIT_CONFIG_VALUE_0"
                  "GIT_EDITOR" "GIT_SEQUENCE_EDITOR"
                  ;; interpreter startup / module load hijacks.
                  "PYTHONHOME" "PYTHONSTARTUP" "GEM_HOME" "GEM_PATH"
                  "RUBYOPT" "LUA_PATH" "R_PROFILE"
                  ;; config-dir, terminfo, resolver, ssh askpass redirection.
                  "XDG_CONFIG_HOME" "TERMINFO" "TERMCAP" "SSH_ASKPASS"
                  "HOSTALIASES" "RES_OPTIONS"))
    (should-not
     (kuro--eval-command-allowed-p (format "setenv %s value" name)))))

(ert-deftest kuro-eval-allows-setenv-benign-names ()
  "The setenv denylist does not block ordinary application variables."
  (dolist (name '("FOO" "MY_APP_TOKEN" "EDITOR_CONFIG" "PATHFINDER"))
    (should (kuro--eval-command-allowed-p (format "setenv %s value" name)))))

(ert-deftest kuro-eval-env-name-denied-p-predicate ()
  "`kuro--eval-env-name-denied-p' flags dangerous names and clears benign ones."
  (should (kuro--eval-env-name-denied-p "LD_PRELOAD"))
  (should (kuro--eval-env-name-denied-p "PATH"))
  (should-not (kuro--eval-env-name-denied-p "PATHFINDER"))
  (should-not (kuro--eval-env-name-denied-p "MY_VAR"))
  ;; A nil denylist disables the check entirely.
  (let ((kuro-eval-denied-env-name-regexp nil))
    (should-not (kuro--eval-env-name-denied-p "LD_PRELOAD"))))

;;; Group 2: kuro--eval-osc51-command dispatch

(ert-deftest kuro-eval-osc51-dispatches-cd-bare ()
  "kuro--eval-osc51-command dispatches bare cd commands."
  (let ((target-dir (make-temp-file "kuro-eval-test-" t)))
    (unwind-protect
        (with-temp-buffer
          (setq default-directory temporary-file-directory)
          (kuro--eval-osc51-command
           (format "cd %s" (shell-quote-argument target-dir)))
          (should (equal default-directory (file-name-as-directory target-dir))))
      (delete-directory target-dir t))))

(ert-deftest kuro-eval-osc51-dispatches-setenv-bare ()
  "kuro--eval-osc51-command dispatches a typed setenv command."
  (let ((var-name "KURO_TEST_VAR"))
    (unwind-protect
        (progn
          (setenv var-name nil)
          (should (kuro--eval-osc51-command (format "setenv %s hello" var-name)))
          (should (equal (getenv var-name) "hello")))
      (setenv var-name nil))))

(ert-deftest kuro-eval-osc51-returns-nil-for-blocked ()
  "kuro--eval-osc51-command returns nil for blocked command."
  (should-not (kuro--eval-osc51-command "delete-file /etc/passwd")))

(ert-deftest kuro-eval-osc51-handles-malformed-command ()
  "kuro--eval-osc51-command handles malformed allowed commands gracefully."
  (should-not (kuro--eval-osc51-command "setenv"))
  (should-not (kuro--eval-osc51-command "setenv FOO")))

(ert-deftest kuro-eval-osc51-rejects-reader-forms-without-reading ()
  "kuro--eval-osc51-command rejects S-expressions without using the Elisp reader."
  (let ((var-name "KURO_TEST_READ_EVAL"))
    (unwind-protect
        (progn
          (setenv var-name nil)
          (should-not
           (kuro--eval-osc51-command
            (format "(setenv #.(setenv %S \"value\") \"ignored\")" var-name)))
          (should-not (getenv var-name)))
      (setenv var-name nil))))

(ert-deftest kuro-eval-osc51-rejects-reader-cycle-syntax ()
  "kuro--eval-osc51-command rejects reader cycle syntax as plain text."
  (let ((var-name "KURO_TEST_CYCLE"))
    (unwind-protect
        (progn
          (should-not
           (kuro--eval-osc51-command
            (format "(setenv \"%s\" . #1=(\"value\" . #1#))" var-name)))
          (should-not (getenv var-name)))
      (setenv var-name nil))))

(ert-deftest kuro-eval-proper-list-p-rejects-cyclic-list-without-looping ()
  "`kuro--eval-proper-list-p' rejects cyclic lists without hanging."
  (let ((cycle (list "x")))
    (setcdr cycle cycle)
    (should-not (kuro--eval-proper-list-p cycle))))

(ert-deftest kuro-eval-osc51-rejects-non-string-arguments ()
  "kuro--eval-osc51-command builders reject non-string OSC 51 arguments."
  (unwind-protect
      (progn
        (setenv "KURO_TEST_NON_STRING" nil)
        (should-error (kuro--eval-osc51-command-form 1))
        (should-error (kuro--eval-osc51-command--build "cd" (list 1) "cd 1"))
        (should-error
         (kuro--eval-osc51-command--build
          "setenv"
          (list "KURO_TEST_NON_STRING" 1)
          "setenv KURO_TEST_NON_STRING 1"))
        (should-not (getenv "KURO_TEST_NON_STRING")))
    (setenv "KURO_TEST_NON_STRING" nil)))

;;; Group 3: defcustom defaults

(ert-deftest kuro-eval-allowed-commands-default-entries ()
  "kuro-eval-allowed-commands default has exact cd and setenv only."
  (should (member "cd" kuro-eval-allowed-commands))
  (should (member "setenv" kuro-eval-allowed-commands))
  (should-not (member "kuro-" kuro-eval-allowed-commands)))

;;; Group 4: kuro--poll-eval-command-updates integration

(ert-deftest kuro-eval-poll-processes-commands ()
  "kuro--poll-eval-command-updates processes commands from the FFI."
  (let ((kuro--initialized t)
        (processed nil))
    (cl-letf (((symbol-function 'kuro-core-poll-eval-commands)
               (lambda (_id) '("cd /tmp")))
              ((symbol-function 'kuro--eval-osc51-command)
               (lambda (cmd) (push cmd processed) nil)))
      (kuro--poll-eval-command-updates)
      (should (equal processed '("cd /tmp"))))))

(ert-deftest kuro-eval-poll-noop-when-no-commands ()
  "`kuro--poll-eval-command-updates' is a no-op when no commands are pending."
  (let (eval-called)
    (cl-letf (((symbol-function 'kuro--poll-eval-commands)
               (lambda () nil))
              ((symbol-function 'kuro--eval-osc51-command)
               (lambda (_cmd) (setq eval-called t))))
      (kuro--poll-eval-command-updates)
      (should-not eval-called))))

(ert-deftest kuro-eval-poll-processes-multiple-commands ()
  "`kuro--poll-eval-command-updates' processes all commands in order."
  (let ((processed nil))
    (cl-letf (((symbol-function 'kuro--poll-eval-commands)
               (lambda () '("cd /tmp" "setenv K v")))
              ((symbol-function 'kuro--eval-osc51-command)
               (lambda (cmd) (push cmd processed))))
      (kuro--poll-eval-command-updates)
      (should (equal (reverse processed) '("cd /tmp" "setenv K v"))))))

(provide 'kuro-eval-test)

;;; kuro-eval-test.el ends here
