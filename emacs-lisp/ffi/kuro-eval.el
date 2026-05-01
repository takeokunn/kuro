;;; kuro-eval.el --- OSC 51 Elisp eval whitelist for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Handles OSC 51 eval command requests from the shell.
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
  "List of command prefixes allowed for OSC 51 eval.
Each entry is a string prefix.  An incoming eval command is executed
only if it starts with one of these prefixes (after whitespace trimming).
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

(defun kuro--eval-osc51-command (cmd)
  "Evaluate a single OSC 51 command CMD if whitelisted.
The command is a string that will be read and evaluated as Elisp.
Returns the evaluation result, or nil if blocked."
  (when (kuro--eval-command-allowed-p cmd)
    (condition-case err
        (eval (car (read-from-string (string-trim cmd))) t)
      (error
       (message "kuro: OSC 51 eval error: %s" (error-message-string err))
       nil))))

(defun kuro--poll-eval-command-updates ()
  "Poll and process pending OSC 51 eval commands.
Each command is filtered through `kuro-eval-command-whitelist' before
evaluation.  Blocked commands are silently dropped."
  (when-let ((commands (kuro--poll-eval-commands)))
    (dolist (cmd commands)
      (kuro--eval-osc51-command cmd))))

(provide 'kuro-eval)

;;; kuro-eval.el ends here
