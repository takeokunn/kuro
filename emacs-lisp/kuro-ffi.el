;;; kuro-ffi.el --- FFI wrapper functions for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides wrapper functions around the Rust FFI bindings.
;; These functions handle the low-level communication with the Rust core.
;;
;; # Architecture
;;
;; All wrappers share the same error-handling pattern via `kuro--call':
;;   1. Guard: only call Rust when `kuro--initialized' is non-nil.
;;   2. Catch: wrap every Rust call in `condition-case' to prevent crashes.
;;   3. Fallback: return a caller-supplied default on error.
;;
;; This eliminates the boilerplate that previously appeared in every function.

;;; Code:

;; These functions are provided by the Rust dynamic module at runtime.
;; declare-function suppresses byte/native compiler "not known to be defined" warnings.
(declare-function kuro-core-init                     "ext:kuro-core" (command rows cols))
(declare-function kuro-core-send-key                 "ext:kuro-core" (bytes))
(declare-function kuro-core-poll-updates             "ext:kuro-core" ())
(declare-function kuro-core-poll-updates-with-faces  "ext:kuro-core" ())
(declare-function kuro-core-resize                   "ext:kuro-core" (rows cols))
(declare-function kuro-core-shutdown                 "ext:kuro-core" ())
(declare-function kuro-core-get-cursor               "ext:kuro-core" ())
(declare-function kuro-core-get-scrollback           "ext:kuro-core" (max-lines))
(declare-function kuro-core-clear-scrollback         "ext:kuro-core" ())
(declare-function kuro-core-set-scrollback-max-lines "ext:kuro-core" (max-lines))
(declare-function kuro-core-get-scrollback-count     "ext:kuro-core" ())
(declare-function kuro-core-get-cursor-visible       "ext:kuro-core" ())
(declare-function kuro-core-get-app-cursor-keys      "ext:kuro-core" ())
(declare-function kuro-core-get-app-keypad           "ext:kuro-core" ())
(declare-function kuro-core-get-mouse-mode           "ext:kuro-core" ())
(declare-function kuro-core-get-mouse-sgr            "ext:kuro-core" ())
(declare-function kuro-core-get-and-clear-title      "ext:kuro-core" ())
(declare-function kuro-core-get-bracketed-paste      "ext:kuro-core" ())
(declare-function kuro-core-scroll-up                "ext:kuro-core" (n))
(declare-function kuro-core-scroll-down              "ext:kuro-core" (n))
(declare-function kuro-core-get-scroll-offset        "ext:kuro-core" ())
(declare-function kuro-core-get-image                "ext:kuro-core" (image-id))
(declare-function kuro-core-poll-image-notifications "ext:kuro-core" ())
(declare-function kuro-core-get-cwd                  "ext:kuro-core" ())
(declare-function kuro-core-get-focus-events         "ext:kuro-core" ())
(declare-function kuro-core-get-sync-output          "ext:kuro-core" ())
(declare-function kuro-core-get-cursor-shape         "ext:kuro-core" ())
(declare-function kuro-core-poll-clipboard-actions   "ext:kuro-core" ())
(declare-function kuro-core-poll-prompt-marks        "ext:kuro-core" ())
(declare-function kuro-core-get-keyboard-flags       "ext:kuro-core" ())
(declare-function kuro-core-get-mouse-pixel          "ext:kuro-core" ())
(declare-function kuro-core-has-pending-output       "ext:kuro-core" ())
(declare-function kuro-core-get-palette-updates      "ext:kuro-core" ())
(declare-function kuro-core-get-default-colors       "ext:kuro-core" ())

(defvar-local kuro--initialized nil
  "Non-nil if Kuro has been initialized.
Buffer-local so that multiple kuro buffers each track their own
session state independently.  When nil, all FFI calls are suppressed.")
(put 'kuro--initialized 'permanent-local t)

(defvar-local kuro--col-to-buf nil
  "Vector mapping grid column index → buffer char offset for the current frame.
Updated each render cycle from `kuro--poll-updates-with-faces'.
Used by `kuro--update-cursor' to translate the terminal cursor column
(which counts grid columns including wide-char placeholders) to the
corresponding Emacs buffer character offset (which skips wide placeholders).
nil means no mapping available; fall back to col = buf-offset (ASCII-only).")
(put 'kuro--col-to-buf 'permanent-local t)

;;; Core dispatch macro

(defmacro kuro--call (fallback &rest body)
  "Guard a Rust FFI call with initialization check and error recovery.

Evaluates BODY only when `kuro--initialized' is non-nil.
On error, logs a message and returns FALLBACK.

Usage:
  (kuro--call nil (kuro-core-get-cursor))
  (kuro--call 0   (kuro-core-get-scroll-offset))"
  (declare (indent 1))
  `(when kuro--initialized
     (condition-case _err
         (progn ,@body)
       (error ,fallback))))

;;; Session lifecycle

;;;###autoload
(defun kuro--init (command &optional rows cols)
  "Initialize Kuro with COMMAND (e.g., \"bash\").
ROWS and COLS specify the initial terminal dimensions.  When omitted, sensible
defaults (24 rows, 80 columns) are used.  Callers should always pass the actual
window dimensions so full-screen programs start with the correct geometry and do
not suffer a SIGWINCH race on their first render.
Returns t if successful, nil otherwise."
  (interactive "sShell command: ")
  (condition-case err
      (let* ((r (or rows 24))
             (c (or cols 80))
             (result (kuro-core-init command r c)))
        (setq kuro--initialized (not (null result)))
        result)
    (error
     (message "Kuro initialization error: %s" err)
     nil)))

;;;###autoload
(defun kuro--shutdown ()
  "Shutdown the Kuro terminal session.
Returns t if successful, nil otherwise."
  (kuro--call nil
    (kuro-core-shutdown)
    (setq kuro--initialized nil)
    t))

;;; Input / output

;;;###autoload
(defun kuro--send-key (data)
  "Send DATA to the terminal.
DATA may be a string or a vector of integer character codes.
Vectors are converted to strings before being passed to the Rust FFI.
Returns t if successful, nil otherwise."
  (kuro--call nil
    (let ((bytes (if (stringp data)
                     data
                   (apply #'string (append data nil)))))
      (kuro-core-send-key bytes))))

;;;###autoload
(defun kuro--poll-updates ()
  "Poll for terminal updates.
Returns a list of (ROW . TEXT) pairs for dirty lines."
  (kuro--call nil (kuro-core-poll-updates)))

;;;###autoload
(defun kuro--poll-updates-with-faces ()
  "Poll for terminal updates with face information.
Returns a list of ((ROW . TEXT) . FACE-RANGES) where FACE-RANGES is
a list of (START-COL END-COL FG BG FLAGS) for each text segment."
  (kuro--call nil (kuro-core-poll-updates-with-faces)))

;;;###autoload
(defun kuro--resize (rows cols)
  "Resize the terminal to ROWS x COLS.
Returns t if successful, nil otherwise."
  (kuro--call nil (kuro-core-resize rows cols)))

;;; Cursor queries

;;;###autoload
(defun kuro--get-cursor ()
  "Get current cursor position.
Returns (ROW . COL) pair."
  (kuro--call '(0 . 0) (kuro-core-get-cursor)))

;;;###autoload
(defun kuro--get-cursor-visible ()
  "Get cursor visibility state (DECTCEM).
Returns t if cursor is visible, nil if hidden."
  (kuro--call t (kuro-core-get-cursor-visible)))

;;;###autoload
(defun kuro--get-cursor-shape ()
  "Get the current cursor shape from the Rust core.
Returns an integer:
  0 = blinking block (default)
  1 = blinking block
  2 = steady block
  3 = blinking underline
  4 = steady underline
  5 = blinking bar
  6 = steady bar
Returns 0 (blinking block) on error."
  (kuro--call 0 (kuro-core-get-cursor-shape)))

;;; Mode queries

;;;###autoload
(defun kuro--get-app-cursor-keys ()
  "Return t if application cursor keys mode (DECCKM) is active."
  (kuro--call nil (kuro-core-get-app-cursor-keys)))

;;;###autoload
(defun kuro--get-app-keypad ()
  "Return t if application keypad mode (DECKPAM) is active, nil otherwise."
  (kuro--call nil (kuro-core-get-app-keypad)))

;;;###autoload
(defun kuro--get-bracketed-paste ()
  "Get the current bracketed paste mode state from Rust core.
Returns t if bracketed paste mode (?2004) is active, nil otherwise."
  (kuro--call nil (kuro-core-get-bracketed-paste)))

;;;###autoload
(defun kuro--get-mouse-mode ()
  "Return the current mouse tracking mode as an integer.
0 = disabled, 1000 = normal, 1002 = button-event, 1003 = any-event."
  (kuro--call 0 (kuro-core-get-mouse-mode)))

;;;###autoload
(defun kuro--get-mouse-sgr ()
  "Return t if SGR extended coordinates mouse mode (mode 1006) is active."
  (kuro--call nil (kuro-core-get-mouse-sgr)))

;;;###autoload
(defun kuro--get-focus-events ()
  "Return t if focus event reporting (mode 1004) is active.
Returns nil if not initialized or focus events are disabled."
  (kuro--call nil (kuro-core-get-focus-events)))

;;;###autoload
(defun kuro--get-sync-output ()
  "Return t if synchronized output mode (DEC 2026) is active.
Returns nil if not initialized or synchronized output is disabled."
  (kuro--call nil (kuro-core-get-sync-output)))

;;;###autoload
(defun kuro--get-keyboard-flags ()
  "Get current Kitty keyboard protocol flags.
Returns an integer bitmask:
  Bit 0 (1): Disambiguate escape codes
  Bit 1 (2): Report event types (press/repeat/release)
  Bit 2 (4): Report alternate keys
  Bit 3 (8): Report all keys as escape codes
  Bit 4 (16): Report associated text
Returns 0 if not initialized or on error."
  (kuro--call 0 (kuro-core-get-keyboard-flags)))

;;; Scrollback

;;;###autoload
(defun kuro--get-scrollback (max-lines)
  "Retrieve up to MAX-LINES lines from the scrollback buffer.
Returns a list of strings, or nil if not initialized."
  (kuro--call nil (kuro-core-get-scrollback max-lines)))

;;;###autoload
(defun kuro--clear-scrollback ()
  "Clear the scrollback buffer.
Returns t if successful, nil otherwise.
Note: callers are responsible for resetting `kuro--scroll-offset' to 0
after this call, since that variable is owned by `kuro-input'."
  (kuro--call nil (kuro-core-clear-scrollback)))

;;;###autoload
(defun kuro--set-scrollback-max-lines (max-lines)
  "Set the maximum scrollback buffer size to MAX-LINES.
Returns t if successful, nil otherwise."
  (kuro--call nil (kuro-core-set-scrollback-max-lines max-lines)))

;;;###autoload
(defun kuro--get-scrollback-count ()
  "Get the number of lines currently in the scrollback buffer.
Returns an integer, or nil if not initialized."
  (kuro--call nil (kuro-core-get-scrollback-count)))

;;;###autoload
(defun kuro--scroll-up (n)
  "Scroll viewport up by N lines into scrollback history."
  (kuro--call nil (kuro-core-scroll-up n)))

;;;###autoload
(defun kuro--scroll-down (n)
  "Scroll viewport down by N lines toward live terminal output."
  (kuro--call nil (kuro-core-scroll-down n)))

(defun kuro--get-scroll-offset ()
  "Get the current scrollback viewport offset from the Rust core."
  (kuro--call 0 (kuro-core-get-scroll-offset)))

;;; OSC events

;;;###autoload
(defun kuro--get-and-clear-title ()
  "Get and atomically clear the window title from Rust core.
Returns the title string if it was dirty, nil otherwise."
  (kuro--call nil (kuro-core-get-and-clear-title)))

;;;###autoload
(defun kuro--get-cwd ()
  "Get current working directory from OSC 7.
Returns a directory string if available, nil otherwise."
  (kuro--call nil (kuro-core-get-cwd)))

;;;###autoload
(defun kuro--poll-clipboard-actions ()
  "Poll for pending OSC 52 clipboard actions from the terminal.
Returns a list of (TYPE . DATA) pairs where TYPE is `write' or `query'.
For `write' actions, DATA is the text string to place on the clipboard.
For `query' actions, DATA is nil (terminal is requesting clipboard contents).
Returns nil if no actions are pending."
  (kuro--call nil (kuro-core-poll-clipboard-actions)))

;;;###autoload
(defun kuro--poll-prompt-marks ()
  "Poll for pending OSC 133 shell prompt mark notifications.
Returns a list of (ROW . MARK-TYPE) pairs where MARK-TYPE is a symbol
such as `prompt-start', `prompt-end', `command-start', or `command-end'.
Returns nil if no marks are pending."
  (kuro--call nil (kuro-core-poll-prompt-marks)))

;;; Kitty Graphics Protocol

;;;###autoload
(defun kuro--get-image (image-id)
  "Retrieve image IMAGE-ID as a base64-encoded PNG string from the Rust core.
Returns the base64 string if the image exists, nil if not found."
  (kuro--call nil (kuro-core-get-image image-id)))

;;;###autoload
(defun kuro--poll-image-notifications ()
  "Poll for pending Kitty Graphics image placement notifications.
Returns a list of (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT) descriptors,
or nil if none are pending."
  (kuro--call nil (kuro-core-poll-image-notifications)))

;;;###autoload
(defun kuro--get-mouse-pixel ()
  "Return t if SGR pixel mouse coordinate mode (?1016) is active."
  (kuro--call nil (kuro-core-get-mouse-pixel)))

;;; Streaming / AI output support

;;;###autoload
(defun kuro--has-pending-output ()
  "Return t if the PTY has unread data waiting to be rendered.
Used for low-latency streaming output detection."
  (kuro--call nil (kuro-core-has-pending-output)))

;;; Color management (OSC 4 / OSC 10/11/12)

;;;###autoload
(defun kuro--get-palette-updates ()
  "Poll for OSC 4 palette overrides.
Returns a list of (INDEX R G B) for each overridden palette entry, or nil."
  (kuro--call nil (kuro-core-get-palette-updates)))

;;;###autoload
(defun kuro--get-default-colors ()
  "Get OSC 10/11/12 default terminal colors if changed since last call.
Returns (FG-ENC BG-ENC CURSOR-ENC) as u32 FFI color values, or nil if unchanged.
FG-ENC/BG-ENC/CURSOR-ENC of #xFF000000 means \\='use default\\='."
  (kuro--call nil (kuro-core-get-default-colors)))

(provide 'kuro-ffi)

;;; kuro-ffi.el ends here
