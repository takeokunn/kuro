;;; kuro-ffi-osc.el --- OSC event, scrollback, and streaming wrappers for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; FFI wrappers for OSC-related terminal features: window title
;; (OSC 2), current working directory (OSC 7), clipboard actions
;; (OSC 52), prompt marks (OSC 133), palette updates (OSC 4),
;; and default color queries (OSC 10/11/12).
;;
;; Also provides Kitty Graphics image retrieval, scrollback buffer
;; management (get/clear/set-max/scroll-up/scroll-down), scroll event
;; consumption, and pending-output detection for streaming.

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
(declare-function kuro-core-poll-eval-commands       "ext:kuro-core" (session-id))
(declare-function kuro-core-get-cwd-host             "ext:kuro-core" (session-id))
(declare-function kuro-core-poll-hyperlink-ranges    "ext:kuro-core" (session-id))

(kuro--define-ffi-getters
 (kuro--get-and-clear-title
  kuro-core-get-and-clear-title nil
  "Get and atomically clear the window title from Rust core.
Returns the title string if it was dirty, nil otherwise.")

 (kuro--get-cwd
  kuro-core-get-cwd nil
  "Get current working directory from OSC 7.
Returns a directory string if available, nil otherwise.")

 (kuro--poll-clipboard-actions
  kuro-core-poll-clipboard-actions nil
  "Poll for pending OSC 52 clipboard actions from the terminal.
Returns a list of (TYPE . DATA) pairs where TYPE is `write' or `query'.
For `write' actions, DATA is the text string to place on the clipboard.
For `query' actions, DATA is nil (terminal is requesting clipboard contents).
Returns nil if no actions are pending.")

 (kuro--poll-prompt-marks
  kuro-core-poll-prompt-marks nil
  "Drain OSC 133 prompt marks from the Rust backend.
Returns a list of proper lists of the form
\(MARK-TYPE ROW COL EXIT-CODE AID DURATION-MS ERR-PATH).
MARK-TYPE is one of \"prompt-start\", \"command-start\", \"command-end\".
AID, DURATION-MS, and ERR-PATH are nil when the shell did not provide
OSC 133 extras (semantic prompt extensions).")

 (kuro--poll-image-notifications
  kuro-core-poll-image-notifications nil
  "Poll for pending Kitty Graphics image placement notifications.
Returns a list of (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT) descriptors,
or nil if none are pending.")

 (kuro--consume-scroll-events
  kuro-core-consume-scroll-events nil
  "Atomically consume pending full-screen scroll event counts from Rust core.
Returns a cons cell (UP . DOWN) when scroll events are pending, nil when
both counts are zero (no scrolling occurred since the last call).
Must be called BEFORE `kuro--poll-updates-with-faces' each frame.")

 (kuro--has-pending-output
  kuro-core-has-pending-output nil
  "Return t if the PTY has unread data waiting to be rendered.
Used for low-latency streaming output detection.
Returns nil if not initialized or on error.")

 (kuro--get-palette-updates
  kuro-core-get-palette-updates nil
  "Poll for OSC 4 palette overrides.
Returns a list of (INDEX R G B) for each overridden palette entry, or nil.")

 (kuro--get-default-colors
  kuro-core-get-default-colors nil
  "Get OSC 10/11/12 default terminal colors if changed since last call.
Returns (FG-ENC BG-ENC CURSOR-ENC) as u32 FFI color values, or nil if unchanged.
FG-ENC/BG-ENC/CURSOR-ENC of #xFF000000 means \='use default\='.")

 (kuro--clear-scrollback
  kuro-core-clear-scrollback nil
  "Clear the scrollback buffer.
Returns t if successful, nil otherwise.
Note: callers are responsible for resetting `kuro--scroll-offset' to 0
after this call, since that variable is owned by `kuro-input'.")

 (kuro--get-scrollback-count
  kuro-core-get-scrollback-count nil
  "Get the number of lines currently in the scrollback buffer.
Returns an integer, or nil if not initialized.")

 (kuro--get-scroll-offset
  kuro-core-get-scroll-offset 0
  "Get the current scrollback viewport offset from the Rust core.
Returns 0 if not initialized.")

 (kuro--poll-eval-commands
  kuro-core-poll-eval-commands nil
  "Poll for pending OSC 51 eval commands from the terminal.
Returns a list of command strings, or nil if none are pending.")

 (kuro--get-cwd-host
  kuro-core-get-cwd-host nil
  "Get the hostname from the last OSC 7 notification.
Returns the hostname string or nil if localhost/unset.")

 (kuro--poll-hyperlink-ranges
  kuro-core-poll-hyperlink-ranges nil
  "Poll for OSC 8 hyperlink ranges on visible terminal rows.
Returns a list of (ROW START END URI) entries, or nil if none."))

(kuro--define-ffi-unary-getters
 (kuro--get-image
  kuro-core-get-image nil image-id
  "Retrieve image IMAGE-ID as a base64-encoded PNG string from the Rust core.
Returns the base64 string if the image exists, nil if not found.")

 (kuro--get-scrollback
  kuro-core-get-scrollback nil max-lines
  "Retrieve up to MAX-LINES lines from the scrollback buffer.
Returns a list of strings, or nil if not initialized.")

 (kuro--set-scrollback-max-lines
  kuro-core-set-scrollback-max-lines nil max-lines
  "Set the maximum scrollback buffer size to MAX-LINES.
Returns t if successful, nil otherwise.")

 (kuro--scroll-up
  kuro-core-scroll-up nil n
  "Scroll viewport up by N lines into scrollback history.")

 (kuro--scroll-down
  kuro-core-scroll-down nil n
  "Scroll viewport down by N lines toward live terminal output."))

(provide 'kuro-ffi-osc)

;;; kuro-ffi-osc.el ends here
