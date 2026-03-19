;;; kuro-input.el --- Keyboard input handling for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This module provides keyboard input handling for the Kuro terminal emulator.
;; It handles printable characters, special keys, arrow keys (in normal and
;; application modes), function keys, modifier combinations, and bracketed paste
;; mode.
;;
;; Mouse tracking is in kuro-input-mouse.el.
;; Bracketed paste is in kuro-input-paste.el.
;; Keymap construction is in kuro-input-keymap.el.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-ffi-osc)

;; Forward reference: kuro--render-cycle is defined in kuro-renderer.el,
;; which is loaded after kuro-input.el.  Declare it here to suppress warnings.
(declare-function kuro--render-cycle "kuro-renderer" ())


;;; Printable Characters

(defun kuro--send-char (char)
  "Send printable character as UTF-8 to PTY."
  (kuro--send-key (string char)))

(defvar-local kuro--pending-render-timer nil
  "One-shot idle timer that fires an immediate render cycle after input.
Buffer-local so that multiple kuro buffers each manage their own timer
independently and cannot cancel or interfere with each other.")
(put 'kuro--pending-render-timer 'permanent-local t)

(defvar kuro-input-echo-delay nil
  "Forward reference; defined in kuro-config.el.")

(defun kuro--schedule-immediate-render ()
  "Schedule a render cycle after `kuro-input-echo-delay' seconds.
The small delay gives the PTY reader thread time to process the shell echo
and deposit it in the channel before we poll for dirty lines and cursor
updates.  Cancels any previously pending timer so rapid typing coalesces
into a single render call."
  (when (timerp kuro--pending-render-timer)
    (cancel-timer kuro--pending-render-timer))
  (let ((buf (current-buffer)))
    (setq kuro--pending-render-timer
          (run-with-idle-timer
           kuro-input-echo-delay nil
           (lambda ()
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (kuro--render-cycle))))))))

(defun kuro--self-insert ()
  "Send the typed character to the PTY (used via remap of self-insert-command).
If last-command-event is a control character (< 32 or = 127), send it as a
control byte directly.  This handles the case where remap catches C-x style
events that were not caught by the explicit Ctrl+letter bindings."
  (interactive)
  (let ((char last-command-event))
    (when (characterp char)
      (kuro--send-char char)
      ;; Schedule an immediate render so the echoed character appears without
      ;; waiting for the next 30/60 fps timer tick.  This is the key mechanism
      ;; that makes SPC and all other printable keys feel instant — the idle
      ;; timer fires as soon as the current command finishes, giving the PTY
      ;; just enough time to echo the character back.
      (kuro--schedule-immediate-render))))


;;; Special Keys

(defun kuro--send-special (byte)
  "Send special key as single byte sequence to PTY and schedule immediate render."
  (kuro--send-key (string byte))
  (kuro--schedule-immediate-render))

(defun kuro--RET ()
  "Send Return key."
  (interactive)
  (kuro--send-key (string ?\r))
  (kuro--schedule-immediate-render))

(defun kuro--TAB ()
  "Send Tab key."
  (interactive)
  (kuro--send-key (string ?\t))
  (kuro--schedule-immediate-render))

(defun kuro--DEL ()
  "Send Delete (backspace) key."
  (interactive)
  (kuro--send-key (string ?\x7f))
  (kuro--schedule-immediate-render))


;;; Helper Function for Key Sequences

(defvar-local kuro--application-cursor-keys-mode nil
  "Cached DECCKM (application cursor keys) mode state from Rust (?1), polled by render cycle.")
(put 'kuro--application-cursor-keys-mode 'permanent-local t)

(defvar-local kuro--scroll-offset 0
  "Current scrollback offset. 0 means live terminal view.")
(put 'kuro--scroll-offset 'permanent-local t)

(defvar-local kuro--app-keypad-mode nil
  "Cached application keypad mode (DECKPAM/DECKPNM) state from Rust, polled by render cycle.
This is intentional P1 scaffolding: the variable is declared and polled now so that the
numeric keypad bindings (kp-0 through kp-9, kp-enter, etc.) can read it when implemented.")
(put 'kuro--app-keypad-mode 'permanent-local t)

(defun kuro--send-key-sequence (normal-sequence application-sequence)
  "Send key sequence, switching between normal and application cursor modes.
NORMAL-SEQUENCE is sent in normal mode.
APPLICATION-SEQUENCE is sent in application cursor keys mode.
Always schedules an immediate render so cursor movement feels instant."
  (kuro--send-key (if kuro--application-cursor-keys-mode
                      application-sequence
                    normal-sequence))
  (kuro--schedule-immediate-render))

;; kuro-input-keys.el is required here — AFTER kuro--send-key-sequence and
;; kuro--send-special are defined — so that those functions are available
;; when kuro-input-keys.el is loaded.
(require 'kuro-input-keys)

(defconst kuro--scroll-to-bottom-sentinel 999999
  "Sentinel value for `kuro-scroll-to-bottom': scrolls past any real content.")

;;;###autoload
(defun kuro-scroll-up ()
  "Scroll back into terminal history by one screenful."
  (interactive)
  (when kuro--initialized
    (let ((lines (window-body-height)))
      (kuro--scroll-up lines)
      (setq kuro--scroll-offset (or (kuro--get-scroll-offset)
                                     (+ kuro--scroll-offset lines)))
      (kuro--render-cycle))))

;;;###autoload
(defun kuro-scroll-down ()
  "Scroll toward live terminal output by one screenful."
  (interactive)
  (when kuro--initialized
    (let ((lines (window-body-height)))
      (kuro--scroll-down lines)
      (setq kuro--scroll-offset (or (kuro--get-scroll-offset)
                                     (max 0 (- kuro--scroll-offset lines))))
      (kuro--render-cycle))))

;;;###autoload
(defun kuro-scroll-bottom ()
  "Return immediately to live terminal output."
  (interactive)
  (when kuro--initialized
    (kuro--scroll-down kuro--scroll-to-bottom-sentinel)
    (setq kuro--scroll-offset (or (kuro--get-scroll-offset) 0))
    (kuro--render-cycle)))


(defun kuro--ctrl-alt-modified (char modifier)
  "Send Ctrl+Alt+CHAR as ESC prefix followed by Ctrl-CHAR.  MODIFIER is ignored."
  (interactive "nChar: \nModifier: ")
  (kuro--send-key (concat (string ?\e) (string (logand char 31))))
  (kuro--schedule-immediate-render))


(defconst kuro--kitty-modifier-offset 1
  "Offset added to the modifier bitmask in the Kitty keyboard protocol.
The Kitty protocol encodes modifiers as (bitmask + 1) on the wire:
no modifier = parameter omitted (implicit 1), shift-only = 2,
alt-only = 3, ctrl-only = 5, shift+ctrl = 6, etc.
Reference: https://sw.kovidgoyal.net/kitty/keyboard-protocol/#modifiers")


;;; Keymap Helpers (used by kuro-input-keymap.el)

(defun kuro--send-ctrl (byte)
  "Send a single control byte (0–31 or 127) to the PTY and schedule render."
  (kuro--send-key (string byte))
  (kuro--schedule-immediate-render))

(defun kuro--send-meta (char)
  "Send ESC + CHAR to the PTY (readline Alt/Meta prefix) and schedule render."
  (kuro--send-key (string ?\e char))
  (kuro--schedule-immediate-render))

;;; Keymap Initialization

;; kuro-input-keymap.el is required here — AFTER all the behavior functions
;; above are defined — so that kuro--build-keymap can reference them via
;; declare-function without a circular require.
(require 'kuro-input-keymap)

;; Build kuro--keymap at load time so it is available immediately for tests
;; and for any kuro-mode buffer that calls (set-keymap-parent kuro-mode-map kuro--keymap).
(kuro--build-keymap)


;;; kuro-send-next-key — bypass keymap exceptions

;;;###autoload
(defun kuro-send-next-key ()
  "Read the next key event and send it directly to the PTY.
This bypasses `kuro-keymap-exceptions', allowing exception keys such as
C-g, M-x, or C-l to reach terminal applications when needed.

Bound to C-c C-q in `kuro-mode-map'."
  (interactive)
  (message "Send key to PTY: ")
  (let* ((event (read-event))
         (modifiers (event-modifiers event))
         (base (event-basic-type event))
         (str (cond
               ;; Control+Meta combined: send ESC + control byte (C-M-x → ESC ^X)
               ((and (memq 'control modifiers) (memq 'meta modifiers) (characterp base))
                (string ?\e (logand base 31)))
               ;; Control modifier: send raw control byte
               ((and (memq 'control modifiers) (characterp base))
                (string (logand base 31)))
               ;; Meta modifier: send ESC + base character
               ((and (memq 'meta modifiers) (characterp base))
                (string ?\e base))
               ;; Plain character (incl. control chars already encoded)
               ((characterp base)
                (string base))
               ;; Named special keys
               ((eq base 'return)    (string ?\r))
               ((eq base 'tab)       (string ?\t))
               ((eq base 'backspace) (string ?\x7f))
               ((eq base 'escape)    (string ?\e))
               (t nil))))
    (if str
        (progn (kuro--send-key str)
               (kuro--schedule-immediate-render))
      (message "kuro-send-next-key: unsupported key event %s"
               (key-description (vector event))))))


;;; Kitty Keyboard Protocol

(defun kuro--encode-kitty-key (key modifiers)
  "Encode KEY with MODIFIERS in Kitty keyboard protocol format.
KEY is a Unicode codepoint integer.
MODIFIERS is a bitmask: shift=1, alt=2, ctrl=4, super=8, hyper=16, meta=32.
Returns the encoded escape sequence string."
  (if (= modifiers 0)
      (format "\e[%du" key)
    (format "\e[%d;%du" key (+ modifiers kuro--kitty-modifier-offset))))

(provide 'kuro-input)

;;; kuro-input.el ends here
