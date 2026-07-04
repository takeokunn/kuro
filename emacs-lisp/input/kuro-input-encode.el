;;; kuro-input-encode.el --- Key encoding helpers for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; This module handles key-event encoding and the explicit bypass command that
;; sends the next key directly to the PTY.

;;; Code:

(require 'kuro-ffi)
;; `kuro--encode-kitty-key' and the KKP modifier constants now live in
;; kuro-input-keys-data.el so kuro-input-keys.el can route through them.
(require 'kuro-input-keys-data)

;; Forward references: defined in kuro-input-render.el.
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())
(declare-function kuro--send-key "kuro-ffi" (str))

(eval-and-compile
  (defconst kuro--named-key-sequences
    '((return    . "\r")
      (tab       . "\t")
      (backspace . "\x7f")
      (escape    . "\e"))
    "Alist mapping named key symbols to their PTY byte sequences.
Used by `kuro--encode-key-event' for special keys in `kuro-send-next-key'."))

(defun kuro--named-key-sequence-dispatch (base sequences)
  "Return the PTY byte sequence for BASE in SEQUENCES, or nil.
SEQUENCES may be a literal alist or the name of a `defconst' table."
  (let ((sequence-list (cond
                        ((symbolp sequences) (symbol-value sequences))
                        ((and (consp sequences) (eq (car sequences) 'quote))
                         (cadr sequences))
                        (t sequences))))
    (cdr (assq base sequence-list))))

(defun kuro--encode-key-event (event)
  "Encode keyboard EVENT as a PTY byte sequence string, or nil if unsupported.
Priority order:
  1. Control+Meta → ESC + control byte  (C-M-x → ESC ^X)
  2. Control      → raw control byte    (C-x   → ^X)
  3. Meta         → ESC + base char     (M-x   → ESC x)
  4. Plain char   → the character itself
  5. Named key    → lookup in `kuro--named-key-sequences'"
  (let* ((modifiers (event-modifiers event))
         (base      (event-basic-type event)))
    (cond
     ((and (memq 'control modifiers) (memq 'meta modifiers) (characterp base))
      (string ?\e (logand base 31)))
     ((and (memq 'control modifiers) (characterp base))
      (string (logand base 31)))
     ((and (memq 'meta modifiers) (characterp base))
      (string ?\e base))
     ((characterp base)
      (string base))
     (t
      (kuro--named-key-sequence-dispatch base kuro--named-key-sequences)))))

;;;###autoload
(defun kuro-send-next-key ()
  "Read the next key event and send it directly to the PTY.
This bypasses `kuro-keymap-exceptions', allowing exception keys to reach
terminal applications when needed.

Bound to \\[kuro-send-next-key] in `kuro-mode-map'."
  (interactive)
  (message "Send key to PTY: ")
  (let* ((event (read-event))
         (str   (kuro--encode-key-event event)))
    (if str
        (progn (kuro--send-key str)
               (kuro--schedule-immediate-render))
      (message "kuro-send-next-key: unsupported key event %s"
               (key-description (vector event))))))

;;; Kitty Keyboard Protocol
;;
;; `kuro--encode-kitty-key', `kuro--kitty-modifier-offset', and the
;; KKP modifier-bit constants moved to kuro-input-keys-data.el so that
;; kuro-input-keys.el (loaded earlier) can route modifier encoding through
;; them.  They remain available here via the (require 'kuro-input-keys-data)
;; above for any caller that loads kuro-input-encode.

(provide 'kuro-input-encode)
;;; kuro-input-encode.el ends here
