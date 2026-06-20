;;; kuro-eval.el --- OSC 51 command whitelist for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Handles OSC 51 command requests from the shell.
;; Commands are security-filtered through a whitelist before execution.
;;
;; The shell integration scripts emit OSC 51 sequences for operations
;; like directory tracking and title updates.  Only whitelisted command
;; patterns are executed; all others are silently dropped.

;;; Code:

(require 'cl-lib)
(require 'kuro-config)
(require 'kuro-ffi-osc)

(declare-function kuro--poll-eval-commands "kuro-ffi-osc" ())

;;; Customization

(defcustom kuro-eval-command-whitelist
  '("cd" "setenv")
  "List of command prefixes allowed for OSC 51 dispatch.
Each entry is a string prefix.  An incoming command is executed only if
it starts with one of these prefixes (after whitespace trimming).
The default allows directory changes and environment variable updates.

Security note: this whitelist prevents arbitrary code execution from
malicious terminal output.  Do not add broad prefixes like \"(\" or
function-namespace prefixes like \"kuro-\" that would permit unintended
functions to be invoked via terminal output."
  :type '(repeat string)
  :group 'kuro)

;;; Core logic

(defun kuro--eval-command-allowed-p (cmd)
  "Return non-nil if CMD is permitted by `kuro-eval-command-whitelist'.
CMD is trimmed; if it starts with `(' the function name is extracted
from the first symbol of the sexp.  Otherwise the raw string is matched
against each prefix in the whitelist."
  (let* ((trimmed (string-trim cmd))
         (name (if (string-prefix-p "(" trimmed)
                   (let ((inner (string-trim (substring trimmed 1))))
                     (if (string-match "\\`\\([^ \t\n)]+\\)" inner)
                         (match-string 1 inner)
                       ""))
                 trimmed)))
    (and (not (string-empty-p name))
         (cl-some (lambda (prefix)
                    (string-prefix-p prefix name))
                  kuro-eval-command-whitelist))))

(defun kuro--eval-osc51-command-form (cmd)
  "Parse CMD into a normalized OSC 51 command form.
The return value is a list whose car is the command name string and
whose cdr are the command arguments.  Sexp commands such as
\"(setenv \\\"FOO\\\" \\\"bar\\\")\" and bare commands such as
\"setenv FOO bar\" are both supported."
  (let ((trimmed (string-trim cmd)))
    (cond
     ((string-empty-p trimmed)
      (error "empty OSC 51 command"))
     ((string-prefix-p "(" trimmed)
      (pcase-let* ((`(,form . ,pos) (read-from-string trimmed)))
        (unless (string-match-p "\\`\\s-*\\'" (substring trimmed pos))
          (error "trailing OSC 51 input: %S" cmd))
        (unless (and (listp form) (symbolp (car-safe form)))
          (error "malformed OSC 51 command: %S" cmd))
        (cons (symbol-name (car form)) (cdr form))))
     (t
      (split-string-and-unquote trimmed)))))

(defun kuro--eval-osc51-dispatch-command (command args)
  "Execute COMMAND with ARGS using explicit OSC 51 dispatch."
  (pcase command
    ("cd"
     (unless (= (length args) 1)
       (error "cd expects exactly 1 argument"))
     (cd (car args)))
    ("setenv"
     (unless (or (= (length args) 2) (= (length args) 3))
       (error "setenv expects 2 or 3 arguments"))
     (apply #'setenv args))
    (_
     (error "unsupported OSC 51 command: %s" command))))

(defun kuro--eval-osc51-command (cmd)
  "Execute a single OSC 51 command CMD if whitelisted.
The command string is parsed and dispatched explicitly.  Returns the
result of the command, or nil if blocked."
  (when (kuro--eval-command-allowed-p cmd)
    (condition-case err
        (pcase-let ((`(,command . ,args) (kuro--eval-osc51-command-form cmd)))
          (kuro--eval-osc51-dispatch-command command args))
      (error
        (message "kuro: OSC 51 command error: %s" (error-message-string err))
        nil))))

(defun kuro--poll-eval-command-updates ()
  "Poll and process pending OSC 51 eval commands.
Each command is filtered through `kuro-eval-command-whitelist' before
dispatch.  Blocked commands are silently dropped."
  (when-let* ((commands (kuro--poll-eval-commands)))
    (dolist (cmd commands)
      (kuro--eval-osc51-command cmd))))

(provide 'kuro-eval)

;;; kuro-eval.el ends here
