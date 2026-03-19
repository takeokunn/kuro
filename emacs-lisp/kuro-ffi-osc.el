;;; kuro-ffi-osc.el --- OSC event, scrollback, and streaming wrappers for Kuro -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Wrappers for OSC title/CWD/clipboard/prompts, Kitty images,
;; scrollback management, scroll events, and streaming detection.

;;; Code:

(require 'kuro-ffi)

(declare-function kuro-core-get-and-clear-title      "ext:kuro-core" ())
(declare-function kuro-core-get-cwd                  "ext:kuro-core" ())
(declare-function kuro-core-poll-clipboard-actions   "ext:kuro-core" ())
(declare-function kuro-core-poll-prompt-marks        "ext:kuro-core" ())
(declare-function kuro-core-get-image                "ext:kuro-core" (image-id))
(declare-function kuro-core-poll-image-notifications "ext:kuro-core" ())
(declare-function kuro-core-consume-scroll-events    "ext:kuro-core" ())
(declare-function kuro-core-has-pending-output       "ext:kuro-core" ())
(declare-function kuro-core-get-palette-updates      "ext:kuro-core" ())
(declare-function kuro-core-get-default-colors       "ext:kuro-core" ())
(declare-function kuro-core-get-scrollback           "ext:kuro-core" (max-lines))
(declare-function kuro-core-clear-scrollback         "ext:kuro-core" ())
(declare-function kuro-core-set-scrollback-max-lines "ext:kuro-core" (max-lines))
(declare-function kuro-core-get-scrollback-count     "ext:kuro-core" ())
(declare-function kuro-core-scroll-up                "ext:kuro-core" (n))
(declare-function kuro-core-scroll-down              "ext:kuro-core" (n))
(declare-function kuro-core-get-scroll-offset        "ext:kuro-core" ())

;;; OSC events

(defun kuro--get-and-clear-title ()
  "Get and atomically clear the window title from Rust core.
Returns the title string if it was dirty, nil otherwise."
  (kuro--call nil (kuro-core-get-and-clear-title)))

(defun kuro--get-cwd ()
  "Get current working directory from OSC 7.
Returns a directory string if available, nil otherwise."
  (kuro--call nil (kuro-core-get-cwd)))

(defun kuro--poll-clipboard-actions ()
  "Poll for pending OSC 52 clipboard actions from the terminal.
Returns a list of (TYPE . DATA) pairs where TYPE is `write' or `query'.
For `write' actions, DATA is the text string to place on the clipboard.
For `query' actions, DATA is nil (terminal is requesting clipboard contents).
Returns nil if no actions are pending."
  (kuro--call nil (kuro-core-poll-clipboard-actions)))

(defun kuro--poll-prompt-marks ()
  "Poll for pending OSC 133 shell prompt mark notifications.
Returns a list of (ROW . MARK-TYPE) pairs where MARK-TYPE is a symbol
such as `prompt-start', `prompt-end', `command-start', or `command-end'.
Returns nil if no marks are pending."
  (kuro--call nil (kuro-core-poll-prompt-marks)))

;;; Kitty Graphics Protocol

(defun kuro--get-image (image-id)
  "Retrieve image IMAGE-ID as a base64-encoded PNG string from the Rust core.
Returns the base64 string if the image exists, nil if not found."
  (kuro--call nil (kuro-core-get-image image-id)))

(defun kuro--poll-image-notifications ()
  "Poll for pending Kitty Graphics image placement notifications.
Returns a list of (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT) descriptors,
or nil if none are pending."
  (kuro--call nil (kuro-core-poll-image-notifications)))

;;; Scroll event polling

(defun kuro--consume-scroll-events ()
  "Atomically consume pending full-screen scroll event counts from the Rust core.
Returns a cons cell (UP . DOWN) when scroll events are pending, nil when
both counts are zero (no scrolling occurred since the last call).
Must be called BEFORE `kuro--poll-updates-with-faces' each frame."
  (kuro--call nil (kuro-core-consume-scroll-events)))

;;; Streaming / AI output support

(defun kuro--has-pending-output ()
  "Return t if the PTY has unread data waiting to be rendered.
Used for low-latency streaming output detection.
Returns nil if not initialized or on error."
  (kuro--call nil (kuro-core-has-pending-output)))

;;; Color management (OSC 4 / OSC 10/11/12)

(defun kuro--get-palette-updates ()
  "Poll for OSC 4 palette overrides.
Returns a list of (INDEX R G B) for each overridden palette entry, or nil."
  (kuro--call nil (kuro-core-get-palette-updates)))

(defun kuro--get-default-colors ()
  "Get OSC 10/11/12 default terminal colors if changed since last call.
Returns (FG-ENC BG-ENC CURSOR-ENC) as u32 FFI color values, or nil if unchanged.
FG-ENC/BG-ENC/CURSOR-ENC of #xFF000000 means \\='use default\\='."
  (kuro--call nil (kuro-core-get-default-colors)))

;;; Scrollback management

(defun kuro--get-scrollback (max-lines)
  "Retrieve up to MAX-LINES lines from the scrollback buffer.
Returns a list of strings, or nil if not initialized."
  (kuro--call nil (kuro-core-get-scrollback max-lines)))

(defun kuro--clear-scrollback ()
  "Clear the scrollback buffer.
Returns t if successful, nil otherwise.
Note: callers are responsible for resetting `kuro--scroll-offset' to 0
after this call, since that variable is owned by `kuro-input'."
  (kuro--call nil (kuro-core-clear-scrollback)))

(defun kuro--set-scrollback-max-lines (max-lines)
  "Set the maximum scrollback buffer size to MAX-LINES.
Returns t if successful, nil otherwise."
  (kuro--call nil (kuro-core-set-scrollback-max-lines max-lines)))

(defun kuro--get-scrollback-count ()
  "Get the number of lines currently in the scrollback buffer.
Returns an integer, or nil if not initialized."
  (kuro--call nil (kuro-core-get-scrollback-count)))

(defun kuro--scroll-up (n)
  "Scroll viewport up by N lines into scrollback history."
  (kuro--call nil (kuro-core-scroll-up n)))

(defun kuro--scroll-down (n)
  "Scroll viewport down by N lines toward live terminal output."
  (kuro--call nil (kuro-core-scroll-down n)))

(defun kuro--get-scroll-offset ()
  "Get the current scrollback viewport offset from the Rust core.
Returns 0 if not initialized."
  (kuro--call 0 (kuro-core-get-scroll-offset)))

(provide 'kuro-ffi-osc)

;;; kuro-ffi-osc.el ends here
