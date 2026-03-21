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

;;; Cursor visibility / shape

(defun kuro--get-cursor-visible ()
  "Get cursor visibility state (DECTCEM).
Returns t if cursor is visible, nil if hidden.
Returns t if not initialized or on error."
  (kuro--call t (kuro-core-get-cursor-visible kuro--session-id)))

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
Returns 0 if not initialized or on error."
  (kuro--call 0 (kuro-core-get-cursor-shape kuro--session-id)))

;;; DEC mode queries

(defun kuro--get-app-cursor-keys ()
  "Return t if application cursor keys mode (DECCKM) is active.
Returns nil if not initialized or on error."
  (kuro--call nil (kuro-core-get-app-cursor-keys kuro--session-id)))

(defun kuro--get-app-keypad ()
  "Return t if application keypad mode (DECKPAM) is active, nil otherwise.
Returns nil if not initialized or on error."
  (kuro--call nil (kuro-core-get-app-keypad kuro--session-id)))

(defun kuro--get-bracketed-paste ()
  "Get the current bracketed paste mode state from Rust core.
Returns t if bracketed paste mode (?2004) is active, nil otherwise.
Returns nil if not initialized or on error."
  (kuro--call nil (kuro-core-get-bracketed-paste kuro--session-id)))

(defun kuro--get-mouse-mode ()
  "Return the current mouse tracking mode as an integer.
0 = disabled, 1000 = normal, 1002 = button-event, 1003 = any-event.
Returns 0 if not initialized or on error."
  (kuro--call 0 (kuro-core-get-mouse-mode kuro--session-id)))

(defun kuro--get-mouse-sgr ()
  "Return t if SGR extended coordinates mouse mode (mode 1006) is active.
Returns nil if not initialized or on error."
  (kuro--call nil (kuro-core-get-mouse-sgr kuro--session-id)))

(defun kuro--get-focus-events ()
  "Return t if focus event reporting (mode 1004) is active.
Returns nil if not initialized or focus events are disabled."
  (kuro--call nil (kuro-core-get-focus-events kuro--session-id)))

(defun kuro--get-sync-output ()
  "Return t if synchronized output mode (DEC 2026) is active.
Returns nil if not initialized or synchronized output is disabled."
  (kuro--call nil (kuro-core-get-sync-output kuro--session-id)))

(defun kuro--get-keyboard-flags ()
  "Get current Kitty keyboard protocol flags.
Returns an integer bitmask:
  Bit 0 (1): Disambiguate escape codes
  Bit 1 (2): Report event types (press/repeat/release)
  Bit 2 (4): Report alternate keys
  Bit 3 (8): Report all keys as escape codes
  Bit 4 (16): Report associated text
Returns 0 if not initialized or on error."
  (kuro--call 0 (kuro-core-get-keyboard-flags kuro--session-id)))

(defun kuro--get-mouse-pixel ()
  "Return t if SGR pixel mouse coordinate mode (?1016) is active.
Returns nil if not initialized or on error."
  (kuro--call nil (kuro-core-get-mouse-pixel kuro--session-id)))

;;; Consolidated queries (PERF-004, PERF-005)

(defun kuro--get-cursor-state ()
  "Get all cursor state in a single FFI call.
Returns a list (ROW COL VISIBLE SHAPE) where:
  ROW, COL: cursor position (integers)
  VISIBLE: t or nil (DECTCEM state)
  SHAPE: DECSCUSR integer (0-6)
Returns nil if not initialized or on error."
  (kuro--call nil (kuro-core-get-cursor-state kuro--session-id)))

(defun kuro--get-terminal-modes ()
  "Get all terminal mode flags in a single FFI call.
Returns a list (APP-CURSOR-KEYS APP-KEYPAD MOUSE-MODE MOUSE-SGR
MOUSE-PIXEL BRACKETED-PASTE KEYBOARD-FLAGS) or nil on error."
  (kuro--call nil (kuro-core-get-terminal-modes kuro--session-id)))

(provide 'kuro-ffi-modes)

;;; kuro-ffi-modes.el ends here
