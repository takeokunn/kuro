;;; kuro-ffi.el --- FFI wrapper functions for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 0.1.0

;;; Commentary:

;; This file provides wrapper functions around the Rust FFI bindings.
;; These functions handle the low-level communication with the Rust core.

;;; Code:

;; These functions are provided by the Rust dynamic module at runtime.
;; declare-function suppresses byte/native compiler "not known to be defined" warnings.
(declare-function kuro-core-init                  "ext:kuro-core" (command))
(declare-function kuro-core-send-key              "ext:kuro-core" (bytes))
(declare-function kuro-core-poll-updates          "ext:kuro-core" ())
(declare-function kuro-core-poll-updates-with-faces "ext:kuro-core" ())
(declare-function kuro-core-resize                "ext:kuro-core" (rows cols))
(declare-function kuro-core-shutdown              "ext:kuro-core" ())
(declare-function kuro-core-get-cursor            "ext:kuro-core" ())

(defvar kuro--initialized nil
  "Non-nil if Kuro has been initialized.")

;;;###autoload
(defun kuro--init (command)
  "Initialize Kuro with COMMAND (e.g., \"bash\").
Returns t if successful, nil otherwise."
  (interactive "sShell command: ")
  (condition-case err
      (let ((result (kuro-core-init command)))
        (setq kuro--initialized (not (null result)))
        result)
    (error
     (message "Kuro initialization error: %s" err)
     nil)))

;;;###autoload
(defun kuro--send-key (bytes)
  "Send BYTES (vector of integers) to the terminal.
Returns t if successful, nil otherwise."
  (when kuro--initialized
    (condition-case err
        (kuro-core-send-key bytes)
      (error
       (message "Kuro send-key error: %s" err)
       nil))))

;;;###autoload
(defun kuro--poll-updates ()
  "Poll for terminal updates.
Returns a list of (ROW . TEXT) pairs for dirty lines."
  (when kuro--initialized
    (condition-case err
        (kuro-core-poll-updates)
      (error
       (message "Kuro poll-updates error: %s" err)
       nil))))

;;;###autoload
(defun kuro--poll-updates-with-faces ()
  "Poll for terminal updates with face information.
Returns a list of ((ROW . TEXT) . FACE-RANGES) where FACE-RANGES is
a list of (START-COL END-COL FG BG FLAGS) for each text segment."
  (when kuro--initialized
    (condition-case err
        (kuro-core-poll-updates-with-faces)
      (error
       (message "Kuro poll-updates-with-faces error: %s" err)
       nil))))

;;;###autoload
(defun kuro--resize (rows cols)
  "Resize the terminal to ROWS x COLS.
Returns t if successful, nil otherwise."
  (when kuro--initialized
    (condition-case err
        (kuro-core-resize rows cols)
      (error
       (message "Kuro resize error: %s" err)
       nil))))

;;;###autoload
(defun kuro--shutdown ()
  "Shutdown the Kuro terminal session.
Returns t if successful, nil otherwise."
  (when kuro--initialized
    (condition-case err
        (progn
          (kuro-core-shutdown)
          (setq kuro--initialized nil)
          t)
      (error
       (message "Kuro shutdown error: %s" err)
       nil))))

;;;###autoload
(defun kuro--get-cursor ()
  "Get current cursor position.
Returns (ROW . COL) pair."
  (when kuro--initialized
    (condition-case err
        (kuro-core-get-cursor)
      (error
       (message "Kuro get-cursor error: %s" err)
       '(0 . 0)))))

(provide 'kuro-ffi)

;;; kuro-ffi.el ends here
