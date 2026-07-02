;;; kuro-eval.el --- OSC 51 typed command dispatch for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Handles OSC 51 command requests from terminal applications.
;; Commands are parsed as a strict string protocol before execution.
;;
;; Only exact known commands with typed, bounded arguments are executed;
;; all others are dropped.  The OSC 51 payload is deliberately not read as
;; Elisp, so reader syntax, reader eval, and arbitrary forms never enter
;; the dispatcher.

;;; Code:

(require 'cl-lib)
(require 'kuro-config)
(require 'kuro-ffi-osc)
(require 'subr-x)

(declare-function kuro--poll-eval-commands "kuro-ffi-osc" ())

;;; Customization

(defcustom kuro-eval-allowed-commands
  '("cd" "setenv")
  "Exact OSC 51 command names allowed for dispatch.
Only exact names in this list and in `kuro-eval--known-commands' are
accepted; prefix matching is deliberately not supported."
  :type '(set (const "cd") (const "setenv"))
  :group 'kuro)

;;; Core logic

(defconst kuro-eval--known-commands
  '("cd" "setenv")
  "OSC 51 commands implemented by the explicit dispatcher.")

(defconst kuro-eval--max-command-bytes 4096
  "Maximum OSC 51 command payload size accepted by the Elisp boundary.")

(defconst kuro-eval--max-env-value-bytes 4096
  "Maximum OSC 51 environment value size accepted by the Elisp boundary.")

(defconst kuro-eval--env-name-regexp
  "\\`[A-Za-z_][A-Za-z0-9_]*\\'"
  "Strict environment variable names accepted by OSC 51 setenv.")

(defconst kuro-eval--control-char-regexp
  "[[:cntrl:]]"
  "Regexp matching control characters rejected from OSC 51 payloads.")

(cl-defstruct (kuro-osc51-command
               (:constructor kuro-osc51-command--create))
  (name nil :type string)
  (args nil :type list))

(defun kuro--eval-proper-list-p (value)
  "Return non-nil when VALUE is a finite proper list."
  (let ((slow value)
        (fast value)
        (ok t))
    (while (and ok (consp fast))
      (setq fast (cdr fast))
      (cond
       ((null fast))
       ((not (consp fast))
        (setq ok nil))
       (t
        (setq fast (cdr fast)
              slow (cdr slow))
        (when (eq slow fast)
          (setq ok nil)))))
    (and ok (null fast))))

(defun kuro--eval-command-allowed-name-p (name)
  "Return non-nil when OSC 51 command NAME is exactly allowed."
  (and (stringp name)
       (member name kuro-eval--known-commands)
       (member name kuro-eval-allowed-commands)))

(defun kuro--eval-string-without-controls-p (value)
  "Return non-nil when VALUE is a string without control characters."
  (and (stringp value)
       (not (string-match-p kuro-eval--control-char-regexp value))))

(defun kuro--eval-local-absolute-directory-p (path)
  "Return non-nil when PATH is an existing local absolute directory."
  (and (kuro--eval-string-without-controls-p path)
       (not (string-empty-p path))
       (file-name-absolute-p path)
       (not (file-remote-p path))
       (file-directory-p path)))

(defun kuro--eval-env-name-p (name)
  "Return non-nil when NAME is a strict environment variable name."
  (and (stringp name)
       (string-match-p kuro-eval--env-name-regexp name)))

(defun kuro--eval-validate-command-string (cmd)
  "Signal an error unless CMD is a bounded OSC 51 command string."
  (unless (stringp cmd)
    (error "OSC 51 command must be a string: %S" cmd))
  (unless (<= (string-bytes cmd) kuro-eval--max-command-bytes)
    (error "OSC 51 command exceeds %d bytes" kuro-eval--max-command-bytes))
  (unless (kuro--eval-string-without-controls-p cmd)
    (error "OSC 51 command contains control characters")))

(defun kuro--eval-osc51-command--build (name args source)
  "Build a typed OSC 51 command from NAME and ARGS parsed from SOURCE."
  (unless (kuro--eval-command-allowed-name-p name)
    (error "Unsupported OSC 51 command: %s" name))
  (unless (and (kuro--eval-proper-list-p args)
               (cl-every #'kuro--eval-string-without-controls-p args))
    (error "OSC 51 command arguments must be strings: %S" source))
  (pcase name
    ("cd"
     (unless (= (length args) 1)
       (error "cd expects exactly 1 argument"))
     (let ((dir (car args)))
       (unless (kuro--eval-local-absolute-directory-p dir)
         (error "cd expects an existing local absolute directory: %S" dir))
       (setq args (list (file-name-as-directory (expand-file-name dir))))))
    ("setenv"
     (unless (= (length args) 2)
       (error "setenv expects exactly 2 arguments"))
     (let ((name (car args))
           (value (cadr args)))
       (unless (kuro--eval-env-name-p name)
         (error "setenv expects a strict variable name: %S" name))
       (unless (<= (string-bytes value) kuro-eval--max-env-value-bytes)
         (error "setenv value exceeds %d bytes" kuro-eval--max-env-value-bytes))))
    (_
     (error "Unsupported OSC 51 command: %s" name)))
  (kuro-osc51-command--create :name name :args args))

(defun kuro--eval-command-allowed-p (cmd)
  "Return non-nil when CMD can be parsed as an allowed typed OSC 51 command."
  (condition-case nil
      (progn
        (kuro--eval-osc51-command-form cmd)
        t)
    (error nil)))

(defun kuro--eval-osc51-command-form (cmd)
  "Parse CMD into a typed OSC 51 command.
The only accepted wire form is a shell-style command string such as
\"setenv FOO bar\".  Elisp reader forms are intentionally rejected."
  (kuro--eval-validate-command-string cmd)
  (let ((trimmed (string-trim cmd)))
    (cond
     ((string-empty-p trimmed)
      (error "Empty OSC 51 command"))
     ((string-prefix-p "(" trimmed)
      (error "OSC 51 Elisp reader forms are unsupported"))
     (t
      (let ((parts (split-string-and-unquote trimmed)))
        (unless parts
          (error "Empty OSC 51 command"))
        (kuro--eval-osc51-command--build
         (car parts)
         (cdr parts)
         cmd))))))

(defun kuro--eval-osc51-dispatch-command (command)
  "Execute typed OSC 51 COMMAND using explicit dispatch."
  (let ((name (kuro-osc51-command-name command))
        (args (kuro-osc51-command-args command)))
    (pcase name
      ("cd"
       (cd (car args)))
      ("setenv"
       (setenv (car args) (cadr args)))
      (_
       (error "Unsupported OSC 51 command: %s" name)))))

(defun kuro--eval-osc51-command (cmd)
  "Execute a single OSC 51 command CMD after parsing it as an allowed command.
Returns the result of the command, or nil if blocked."
  (condition-case err
      (kuro--eval-osc51-dispatch-command
       (kuro--eval-osc51-command-form cmd))
    (error
     (message "kuro: OSC 51 command error: %s" (error-message-string err))
     nil)))

(defun kuro--poll-eval-command-updates ()
  "Poll and process pending OSC 51 command payloads.
Each command is parsed through `kuro-eval-allowed-commands' before
dispatch.  Blocked commands are silently dropped."
  (when-let* ((commands (kuro--poll-eval-commands)))
    (dolist (cmd commands)
      (kuro--eval-osc51-command cmd))))

(provide 'kuro-eval)

;;; kuro-eval.el ends here
