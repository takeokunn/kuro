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
(declare-function kuro-core-poll-notifications       "ext:kuro-core" (session-id))
(declare-function kuro-core-notify-action-response   "ext:kuro-core" (session-id id button close))
(declare-function kuro-core-poll-prompt-marks        "ext:kuro-core" (session-id))
(declare-function kuro-core-get-image                "ext:kuro-core" (session-id image-id))
(declare-function kuro-core-poll-image-notifications "ext:kuro-core" (session-id))
(declare-function kuro-core-poll-placeholder-placements "ext:kuro-core" (session-id))
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
(declare-function kuro-core-poll-text-size-ranges    "ext:kuro-core" (session-id))
(declare-function kuro-core-get-progress             "ext:kuro-core" (session-id))
(declare-function kuro-core-poll-user-vars           "ext:kuro-core" (session-id))
(declare-function kuro-core-get-remote-host          "ext:kuro-core" (session-id))
(declare-function kuro-core-image-frame-count        "ext:kuro-core" (session-id image-id))
(declare-function kuro-core-image-frame-png          "ext:kuro-core" (session-id image-id frame-index))
(declare-function kuro-core-image-frame-gap          "ext:kuro-core" (session-id image-id frame-index))
(declare-function kuro-core-image-animation-state    "ext:kuro-core" (session-id image-id))

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
Returns a list of (TAG PAYLOAD TARGET) 3-element lists where TAG is
`write' or `query'.
For `write' actions, PAYLOAD is the text string to place on the selection.
For `query' actions, PAYLOAD is nil (terminal is requesting contents).
TARGET is the selection-target string from the OSC 52 field — one of
\"clipboard\", \"primary\", or \"select\" — used to route the action to the
correct Emacs selection (see `kuro--clipboard-write').
Malformed actions, unsupported targets, and legacy 2-element actions are
ignored by the Lisp-side dispatcher.
Returns nil if no actions are pending.")

 (kuro--poll-notifications
  kuro-core-poll-notifications nil
  "Poll for pending OSC 9 / OSC 777 desktop notifications from the terminal.
Returns a list of (TITLE . BODY) cons cells, where TITLE is a string
\(OSC 777) or nil (the iTerm2 OSC 9 form) and BODY is the notification
text.  Returns nil if no notifications are pending.")

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

 (kuro--poll-placeholder-placements
  kuro-core-poll-placeholder-placements nil
  "Poll for Kitty Unicode-placeholder (U+10EEEE) image regions on the grid.
Returns a list of placeholder-region descriptors, each of the form
\(IMAGE-ID PLACEMENT-ID SCREEN-ROW SCREEN-COL CELL-COLS CELL-ROWS
IMG-ROW IMG-COL IMG-ROWS IMG-COLS), or nil when no placeholders are present.
SCREEN-ROW/SCREEN-COL are the 0-based top-left of the placeholder rectangle,
CELL-COLS x CELL-ROWS its size in terminal cells, IMG-ROW/IMG-COL the tile
origin within the image grid, and IMG-ROWS x IMG-COLS the total image-grid
extent the rectangle covers — so each cell renders its TILE of the image
\(fit-to-rectangle).  Unlike `kuro--poll-image-notifications', this is a
non-draining query re-derived from the grid each frame, so the placeholder
image survives scrolling and reflow like the underlying text.")

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
  "Poll for pending OSC 51 command payloads from the terminal.
Returns a list of command strings, or nil if none are pending.")

 (kuro--get-cwd-host
  kuro-core-get-cwd-host nil
  "Get the hostname from the last OSC 7 notification.
Returns the hostname string or nil if localhost/unset.")

 (kuro--get-progress
  kuro-core-get-progress nil
  "Poll the ConEmu OSC 9;4 progress state if it changed since the last call.
Returns a cons cell (STATE . PERCENT) when the progress state changed
\(clearing the dirty flag), or nil when unchanged.
STATE is 0=none, 1=set, 2=error, 3=indeterminate, 4=warning; PERCENT is
0-100 (0 for the stateless none/indeterminate variants).")

 (kuro--poll-user-vars-raw
  kuro-core-poll-user-vars nil
  "Poll iTerm2 OSC 1337 `SetUserVar' user variables if they changed.
Returns a list of (NAME . VALUE) cons cells (the full current set) when the
user-vars changed since the last call (clearing the dirty flag), or nil when
unchanged.  VALUE is the base64-decoded user-variable value string.")

 (kuro--get-remote-host
  kuro-core-get-remote-host nil
  "Get the iTerm2 OSC 1337 `RemoteHost=<user@host>' value if it changed.
Returns the remote-host string when updated since the last call (clearing the
dirty flag), or nil otherwise.")

 (kuro--poll-hyperlink-ranges
  kuro-core-poll-hyperlink-ranges nil
  "Poll for OSC 8 hyperlink ranges on visible terminal rows.
Returns a list of (ROW START END URI) entries, or nil if none.")

 (kuro--poll-text-size-ranges
  kuro-core-poll-text-size-ranges nil
  "Poll for Kitty text-sizing (OSC 66) ranges on visible terminal rows.
Returns a list of (ROW START END SCALED-PERMILLE) entries, or nil if none.
START and END are in-row character offsets; SCALED-PERMILLE is the effective
size multiplier times 1000 (e.g. 2000 = 2x, 500 = half size).  Rows without
any sized cells are omitted."))

(kuro--define-ffi-unary-getters
 (kuro--get-image
  kuro-core-get-image nil image-id
  "Retrieve image IMAGE-ID as a base64-encoded PNG string from the Rust core.
Returns the base64 string if the image exists, nil if not found.")

 (kuro--image-frame-count
  kuro-core-image-frame-count 0 image-id
  "Return the number of Kitty animation frames for IMAGE-ID.
Returns 0 for a still image or when the image is unknown.")

 (kuro--image-animation-state
  kuro-core-image-animation-state nil image-id
  "Return Kitty animation playback state for IMAGE-ID.
Returns (PLAYING CURRENT-FRAME LOOP-COUNT) where CURRENT-FRAME is 1-based
and LOOP-COUNT of 0 means infinite, or nil if the image is unknown.")

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

(kuro--define-ffi-binary-getters
 (kuro--image-frame-png
  kuro-core-image-frame-png nil image-id frame-index
  "Render Kitty animation frame FRAME-INDEX (0-based) of IMAGE-ID.
Returns a base64-encoded PNG string, or nil if the frame does not exist.")

 (kuro--image-frame-gap
  kuro-core-image-frame-gap 0 image-id frame-index
  "Return the display gap (ms) for Kitty animation frame FRAME-INDEX of IMAGE-ID.
Returns 0 when the frame does not exist."))

(defun kuro--notify-action-response (session-id id button close)
  "Send an OSC 99 notification action response back to the terminal application.
SESSION-ID is the Rust session that emitted the notification.  ID is the OSC 99
`i=<id>' notification id string.  BUTTON is a 0-based button index, or any
negative integer for plain activation (no button).  CLOSE is non-nil for the
`p=close' close-report variant.

The response (`OSC 99 ; i=<ID> ; <BUTTON> ST') is enqueued in the Rust core and
flushed to the PTY on the next poll, exactly like a DSR/DA reply.  Returns t on
success, nil if the session is missing or the module is unavailable."
  (when (and kuro--initialized (stringp id))
    (condition-case err
        (kuro-core-notify-action-response
         session-id id (or button -1) (if close 1 0))
      (error
       (when kuro-log-errors (kuro--log err))
       nil))))

(provide 'kuro-ffi-osc)

;;; kuro-ffi-osc.el ends here
