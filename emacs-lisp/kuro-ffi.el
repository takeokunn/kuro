;;; kuro-ffi.el --- FFI wrapper functions for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

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
(declare-function kuro-core-get-scrollback        "ext:kuro-core" (max-lines))
(declare-function kuro-core-clear-scrollback      "ext:kuro-core" ())
(declare-function kuro-core-set-scrollback-max-lines "ext:kuro-core" (max-lines))
(declare-function kuro-core-get-scrollback-count  "ext:kuro-core" ())
(declare-function kuro-core-get-cursor-visible    "ext:kuro-core" ())
(declare-function kuro-core-get-app-cursor-keys   "ext:kuro-core" ())
(declare-function kuro-core-get-app-keypad        "ext:kuro-core" ())
(declare-function kuro-core-get-mouse-mode        "ext:kuro-core" ())
(declare-function kuro-core-get-mouse-sgr         "ext:kuro-core" ())
(declare-function kuro-core-get-and-clear-title   "ext:kuro-core" ())
(declare-function kuro-core-get-bracketed-paste   "ext:kuro-core" ())
(declare-function kuro-core-scroll-up        "ext:kuro-core" (n))
(declare-function kuro-core-scroll-down      "ext:kuro-core" (n))
(declare-function kuro-core-get-scroll-offset "ext:kuro-core" ())
(declare-function kuro-core-get-image                "ext:kuro-core" (image-id))
(declare-function kuro-core-poll-image-notifications "ext:kuro-core" ())

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
(defun kuro--send-key (data)
  "Send DATA to the terminal.
DATA may be a string or a vector of integer character codes.
Vectors are converted to strings before being passed to the Rust FFI.
Returns t if successful, nil otherwise."
  (when kuro--initialized
    (condition-case err
        (let ((bytes (if (stringp data)
                         data
                       (apply #'string (append data nil)))))
          (kuro-core-send-key bytes))
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

;;;###autoload
(defun kuro--get-scrollback (max-lines)
  "Retrieve up to MAX-LINES lines from the scrollback buffer.
Returns a list of strings, or nil if not initialized."
  (when kuro--initialized
    (condition-case err
        (kuro-core-get-scrollback max-lines)
      (error
       (message "Kuro get-scrollback error: %s" err)
       nil))))

;;;###autoload
(defun kuro--clear-scrollback ()
  "Clear the scrollback buffer.
Returns t if successful, nil otherwise."
  (when kuro--initialized
    (condition-case err
        (progn
          (kuro-core-clear-scrollback)
          (setq kuro--scroll-offset 0))
      (error
       (message "Kuro clear-scrollback error: %s" err)
       nil))))

;;;###autoload
(defun kuro--set-scrollback-max-lines (max-lines)
  "Set the maximum scrollback buffer size to MAX-LINES.
Returns t if successful, nil otherwise."
  (when kuro--initialized
    (condition-case err
        (kuro-core-set-scrollback-max-lines max-lines)
      (error
       (message "Kuro set-scrollback-max-lines error: %s" err)
       nil))))

;;;###autoload
(defun kuro--get-scrollback-count ()
  "Get the number of lines currently in the scrollback buffer.
Returns an integer, or nil if not initialized."
  (when kuro--initialized
    (condition-case err
        (kuro-core-get-scrollback-count)
      (error
       (message "Kuro get-scrollback-count error: %s" err)
       nil))))

;;;###autoload
(defun kuro--get-cursor-visible ()
  "Get cursor visibility state (DECTCEM).
Returns t if cursor is visible, nil if hidden."
  (when kuro--initialized
    (condition-case err
        (kuro-core-get-cursor-visible)
      (error
       (message "Kuro get-cursor-visible error: %s" err)
       t))))

;;;###autoload
(defun kuro--get-app-cursor-keys ()
  "Return t if application cursor keys mode (DECCKM) is active."
  (when kuro--initialized
    (condition-case nil
        (kuro-core-get-app-cursor-keys)
      (error nil))))

;;;###autoload
(defun kuro--get-app-keypad ()
  "Return t if application keypad mode (DECKPAM) is active, nil otherwise."
  (when kuro--initialized
    (condition-case nil
        (kuro-core-get-app-keypad)
      (error nil))))

;;;###autoload
(defun kuro--get-mouse-mode ()
  "Return the current mouse tracking mode as an integer.
0 = disabled, 1000 = normal, 1002 = button-event, 1003 = any-event."
  (when kuro--initialized
    (condition-case nil
        (kuro-core-get-mouse-mode)
      (error 0))))

;;;###autoload
(defun kuro--get-mouse-sgr ()
  "Return t if SGR extended coordinates mouse mode (mode 1006) is active."
  (when kuro--initialized
    (condition-case nil
        (kuro-core-get-mouse-sgr)
      (error nil))))

;;;###autoload
(defun kuro--get-and-clear-title ()
  "Get and atomically clear the window title from Rust core.
Returns the title string if it was dirty, nil otherwise."
  (when kuro--initialized
    (condition-case err
        (kuro-core-get-and-clear-title)
      (error (message "kuro: get-and-clear-title error: %s" err) nil))))

;;;###autoload
(defun kuro--get-bracketed-paste ()
  "Get the current bracketed paste mode state from Rust core.
Returns t if bracketed paste mode (?2004) is active, nil otherwise."
  (when kuro--initialized
    (condition-case err
        (kuro-core-get-bracketed-paste)
      (error (message "kuro: get-bracketed-paste error: %s" err) nil))))

;;;###autoload
(defun kuro--scroll-up (n)
  "Scroll viewport up by N lines into scrollback history."
  (when kuro--initialized
    (condition-case err
        (kuro-core-scroll-up n)
      (error (message "Kuro scroll-up error: %s" err) nil))))

;;;###autoload
(defun kuro--scroll-down (n)
  "Scroll viewport down by N lines toward live terminal output."
  (when kuro--initialized
    (condition-case err
        (kuro-core-scroll-down n)
      (error (message "Kuro scroll-down error: %s" err) nil))))

(defun kuro--get-scroll-offset ()
  "Get the current scrollback viewport offset from the Rust core."
  (when kuro--initialized
    (condition-case err
        (kuro-core-get-scroll-offset)
      (error (message "Kuro get-scroll-offset error: %s" err) 0))))

;;;###autoload
(defun kuro--get-image (image-id)
  "Retrieve image IMAGE-ID as a base64-encoded PNG string from the Rust core.
Returns the base64 string if the image exists, nil if not found."
  (when kuro--initialized
    (condition-case err
        (kuro-core-get-image image-id)
      (error
       (message "kuro: get-image error for id %d: %s" image-id err)
       nil))))

;;;###autoload
(defun kuro--poll-image-notifications ()
  "Poll for pending Kitty Graphics image placement notifications.
Returns a list of (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT) descriptors,
or nil if none are pending."
  (when kuro--initialized
    (condition-case err
        (kuro-core-poll-image-notifications)
      (error
       (message "kuro: poll-image-notifications error: %s" err)
       nil))))

(provide 'kuro-ffi)

;;; kuro-ffi.el ends here
