;;; kuro-ffi-osc.el --- OSC event, scrollback, and streaming wrappers for Kuro -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Wrappers for OSC title/CWD/clipboard/prompts, Kitty images,
;; scrollback management, scroll events, and streaming detection.

;;; Code:

(require 'kuro-ffi)

(declare-function kuro-core-get-and-clear-title      "ext:kuro-core" (session-id))
(declare-function kuro-core-get-cwd                  "ext:kuro-core" (session-id))
(declare-function kuro-core-poll-clipboard-actions   "ext:kuro-core" (session-id))
(declare-function kuro-core-poll-prompt-marks        "ext:kuro-core" (session-id))
(declare-function kuro-core-get-image                "ext:kuro-core" (session-id image-id))
(declare-function kuro-core-poll-image-notifications "ext:kuro-core" (session-id))
(declare-function kuro-core-consume-scroll-events    "ext:kuro-core" (session-id))
(declare-function kuro-core-has-pending-output       "ext:kuro-core" (session-id))
(declare-function kuro-core-get-palette-updates      "ext:kuro-core" (session-id))
(declare-function kuro-core-get-default-colors       "ext:kuro-core" (session-id))
(declare-function kuro-core-get-scrollback           "ext:kuro-core" (session-id max-lines))
(declare-function kuro-core-clear-scrollback         "ext:kuro-core" (session-id))
(declare-function kuro-core-set-scrollback-max-lines "ext:kuro-core" (session-id max-lines))
(declare-function kuro-core-get-scrollback-count     "ext:kuro-core" (session-id))
(declare-function kuro-core-scroll-up                "ext:kuro-core" (session-id n))
(declare-function kuro-core-scroll-down              "ext:kuro-core" (session-id n))
(declare-function kuro-core-get-scroll-offset        "ext:kuro-core" (session-id))

;;; OSC events

(kuro--def-ffi-getter kuro--get-and-clear-title
  kuro-core-get-and-clear-title nil
  "Get and atomically clear the window title from Rust core.
Returns the title string if it was dirty, nil otherwise.")

(kuro--def-ffi-getter kuro--get-cwd
  kuro-core-get-cwd nil
  "Get current working directory from OSC 7.
Returns a directory string if available, nil otherwise.")

(kuro--def-ffi-getter kuro--poll-clipboard-actions
  kuro-core-poll-clipboard-actions nil
  "Poll for pending OSC 52 clipboard actions from the terminal.
Returns a list of (TYPE . DATA) pairs where TYPE is `write' or `query'.
For `write' actions, DATA is the text string to place on the clipboard.
For `query' actions, DATA is nil (terminal is requesting clipboard contents).
Returns nil if no actions are pending.")

(kuro--def-ffi-getter kuro--poll-prompt-marks
  kuro-core-poll-prompt-marks nil
  "Poll for pending OSC 133 shell prompt mark notifications.
Returns a list of (ROW . MARK-TYPE) pairs where MARK-TYPE is a symbol
such as `prompt-start', `prompt-end', `command-start', or `command-end'.
Returns nil if no marks are pending.")

;;; Kitty Graphics Protocol

(kuro--def-ffi-unary kuro--get-image
  kuro-core-get-image nil image-id
  "Retrieve image IMAGE-ID as a base64-encoded PNG string from the Rust core.
Returns the base64 string if the image exists, nil if not found.")

(kuro--def-ffi-getter kuro--poll-image-notifications
  kuro-core-poll-image-notifications nil
  "Poll for pending Kitty Graphics image placement notifications.
Returns a list of (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT) descriptors,
or nil if none are pending.")

;;; Scroll event polling

(kuro--def-ffi-getter kuro--consume-scroll-events
  kuro-core-consume-scroll-events nil
  "Atomically consume pending full-screen scroll event counts from the Rust core.
Returns a cons cell (UP . DOWN) when scroll events are pending, nil when
both counts are zero (no scrolling occurred since the last call).
Must be called BEFORE `kuro--poll-updates-with-faces' each frame.")

;;; Streaming / AI output support

(kuro--def-ffi-getter kuro--has-pending-output
  kuro-core-has-pending-output nil
  "Return t if the PTY has unread data waiting to be rendered.
Used for low-latency streaming output detection.
Returns nil if not initialized or on error.")

;;; Color management (OSC 4 / OSC 10/11/12)

(kuro--def-ffi-getter kuro--get-palette-updates
  kuro-core-get-palette-updates nil
  "Poll for OSC 4 palette overrides.
Returns a list of (INDEX R G B) for each overridden palette entry, or nil.")

(kuro--def-ffi-getter kuro--get-default-colors
  kuro-core-get-default-colors nil
  "Get OSC 10/11/12 default terminal colors if changed since last call.
Returns (FG-ENC BG-ENC CURSOR-ENC) as u32 FFI color values, or nil if unchanged.
FG-ENC/BG-ENC/CURSOR-ENC of #xFF000000 means \\='use default\\='.")

;;; Scrollback management

(kuro--def-ffi-unary kuro--get-scrollback
  kuro-core-get-scrollback nil max-lines
  "Retrieve up to MAX-LINES lines from the scrollback buffer.
Returns a list of strings, or nil if not initialized.")

(kuro--def-ffi-getter kuro--clear-scrollback
  kuro-core-clear-scrollback nil
  "Clear the scrollback buffer.
Returns t if successful, nil otherwise.
Note: callers are responsible for resetting `kuro--scroll-offset' to 0
after this call, since that variable is owned by `kuro-input'.")

(kuro--def-ffi-unary kuro--set-scrollback-max-lines
  kuro-core-set-scrollback-max-lines nil max-lines
  "Set the maximum scrollback buffer size to MAX-LINES.
Returns t if successful, nil otherwise.")

(kuro--def-ffi-getter kuro--get-scrollback-count
  kuro-core-get-scrollback-count nil
  "Get the number of lines currently in the scrollback buffer.
Returns an integer, or nil if not initialized.")

(kuro--def-ffi-unary kuro--scroll-up
  kuro-core-scroll-up nil n
  "Scroll viewport up by N lines into scrollback history.")

(kuro--def-ffi-unary kuro--scroll-down
  kuro-core-scroll-down nil n
  "Scroll viewport down by N lines toward live terminal output.")

(kuro--def-ffi-getter kuro--get-scroll-offset
  kuro-core-get-scroll-offset 0
  "Get the current scrollback viewport offset from the Rust core.
Returns 0 if not initialized.")

(provide 'kuro-ffi-osc)

;;; kuro-ffi-osc.el ends here
