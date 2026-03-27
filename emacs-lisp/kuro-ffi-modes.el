;;; kuro-ffi-modes.el --- Terminal mode query wrappers for Kuro -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Wrappers for DEC mode queries, mouse mode, keyboard protocol flags.

;;; Code:

(require 'kuro-ffi)

(declare-function kuro-core-get-cursor-visible   "ext:kuro-core" (session-id))
(declare-function kuro-core-get-cursor-shape     "ext:kuro-core" (session-id))
(declare-function kuro-core-get-cursor-state     "ext:kuro-core" (session-id))
(declare-function kuro-core-get-app-cursor-keys  "ext:kuro-core" (session-id))
(declare-function kuro-core-get-app-keypad       "ext:kuro-core" (session-id))
(declare-function kuro-core-get-bracketed-paste  "ext:kuro-core" (session-id))
(declare-function kuro-core-get-mouse-mode       "ext:kuro-core" (session-id))
(declare-function kuro-core-get-mouse-sgr        "ext:kuro-core" (session-id))
(declare-function kuro-core-get-focus-events     "ext:kuro-core" (session-id))
(declare-function kuro-core-get-sync-output      "ext:kuro-core" (session-id))
(declare-function kuro-core-get-keyboard-flags   "ext:kuro-core" (session-id))
(declare-function kuro-core-get-mouse-pixel      "ext:kuro-core" (session-id))
(declare-function kuro-core-get-terminal-modes   "ext:kuro-core" (session-id))

;;; Table-driven getter generation

(defmacro kuro--define-ffi-getters (&rest entries)
  "Expand each ENTRIES element into a `kuro--def-ffi-getter' call.
Each entry has the form (NAME CORE-FN DEFAULT DOC).
Using a macro (rather than dolist+eval) ensures every getter is a
proper top-level `defun', so `describe-function' shows its docstring."
  (declare (indent 0))
  `(progn
     ,@(mapcar (lambda (entry)
                 `(kuro--def-ffi-getter
                   ,(nth 0 entry)
                   ,(nth 1 entry)
                   ,(nth 2 entry)
                   ,(nth 3 entry)))
               entries)))

(kuro--define-ffi-getters
 ;;; Cursor visibility / shape
 (kuro--get-cursor-visible
  kuro-core-get-cursor-visible t
  "Get cursor visibility state (DECTCEM).
Returns t if cursor is visible, nil if hidden.
Returns t if not initialized or on error.")

 (kuro--get-cursor-shape
  kuro-core-get-cursor-shape 0
  "Get the current cursor shape from the Rust core.
Returns an integer:
  0 = blinking block (default)
  1 = blinking block
  2 = steady block
  3 = blinking underline
  4 = steady underline
  5 = blinking bar
  6 = steady bar
Returns 0 if not initialized or on error.")

 ;;; DEC mode queries
 (kuro--get-app-cursor-keys
  kuro-core-get-app-cursor-keys nil
  "Return t if application cursor keys mode (DECCKM) is active.
Returns nil if not initialized or on error.")

 (kuro--get-app-keypad
  kuro-core-get-app-keypad nil
  "Return t if application keypad mode (DECKPAM) is active, nil otherwise.
Returns nil if not initialized or on error.")

 (kuro--get-bracketed-paste
  kuro-core-get-bracketed-paste nil
  "Get the current bracketed paste mode state from Rust core.
Returns t if bracketed paste mode (?2004) is active, nil otherwise.
Returns nil if not initialized or on error.")

 (kuro--get-mouse-mode
  kuro-core-get-mouse-mode 0
  "Return the current mouse tracking mode as an integer.
0 = disabled, 1000 = normal, 1002 = button-event, 1003 = any-event.
Returns 0 if not initialized or on error.")

 (kuro--get-mouse-sgr
  kuro-core-get-mouse-sgr nil
  "Return t if SGR extended coordinates mouse mode (mode 1006) is active.
Returns nil if not initialized or on error.")

 (kuro--get-focus-events
  kuro-core-get-focus-events nil
  "Return t if focus event reporting (mode 1004) is active.
Returns nil if not initialized or focus events are disabled.")

 (kuro--get-sync-output
  kuro-core-get-sync-output nil
  "Return t if synchronized output mode (DEC 2026) is active.
Returns nil if not initialized or synchronized output is disabled.")

 (kuro--get-keyboard-flags
  kuro-core-get-keyboard-flags 0
  "Get current Kitty keyboard protocol flags.
Returns an integer bitmask:
  Bit 0 (1): Disambiguate escape codes
  Bit 1 (2): Report event types (press/repeat/release)
  Bit 2 (4): Report alternate keys
  Bit 3 (8): Report all keys as escape codes
  Bit 4 (16): Report associated text
Returns 0 if not initialized or on error.")

 (kuro--get-mouse-pixel
  kuro-core-get-mouse-pixel nil
  "Return t if SGR pixel mouse coordinate mode (?1016) is active.
Returns nil if not initialized or on error.")

 ;;; Consolidated queries (PERF-004, PERF-005)
 (kuro--get-cursor-state
  kuro-core-get-cursor-state nil
  "Get all cursor state in a single FFI call.
Returns a list (ROW COL VISIBLE SHAPE) where:
  ROW, COL: cursor position (integers)
  VISIBLE: t or nil (DECTCEM state)
  SHAPE: DECSCUSR integer (0-6)
Returns nil if not initialized or on error.")

 (kuro--get-terminal-modes
  kuro-core-get-terminal-modes nil
  "Get all terminal mode flags in a single FFI call.
Returns a list (APP-CURSOR-KEYS APP-KEYPAD MOUSE-MODE MOUSE-SGR
MOUSE-PIXEL BRACKETED-PASTE KEYBOARD-FLAGS) or nil on error."))

(provide 'kuro-ffi-modes)

;;; kuro-ffi-modes.el ends here
