;;; kuro-input.el --- Keyboard input handling for Kuro terminal emulator -*- lexical-binding: t -*-

;;; Commentary:

;; This module provides keyboard input handling for the Kuro terminal emulator.
;; It handles printable characters, special keys, arrow keys (in normal and
;; application modes), function keys, modifier combinations, and bracketed paste
;; mode.

;;; Code:

(require 'kuro-ffi)


;;; Printable Characters

(defun kuro--send-char (char)
  "Send printable character as UTF-8 to PTY."
  (kuro--send-key (string char)))

(defun kuro--self-insert ()
  "Send the typed character to the PTY (used via remap of self-insert-command)."
  (interactive)
  (kuro--send-char last-command-event))


;;; Special Keys

(defun kuro--send-special (byte)
  "Send special key as single byte sequence to PTY."
  (kuro--send-key (string byte)))

(defun kuro--RET ()
  "Send Return key."
  (interactive)
  (kuro--send-special ?\r))

(defun kuro--TAB ()
  "Send Tab key."
  (interactive)
  (kuro--send-special ?\t))

(defun kuro--DEL ()
  "Send Delete (backspace) key."
  (interactive)
  (kuro--send-special ?\x7f))


;;; Helper Function for Key Sequences

(defvar kuro--application-cursor-keys-mode nil
  "Non-nil when application cursor keys mode is active.")

(defun kuro--send-key-sequence (normal-sequence application-sequence)
  "Send key sequence, switching between normal and application cursor modes.
NORMAL-SEQUENCE is sent in normal mode.
APPLICATION-SEQUENCE is sent in application cursor keys mode."
  (kuro--send-key (if kuro--application-cursor-keys-mode
                      application-sequence
                    normal-sequence)))


;;; Arrow Keys (Normal and Application Mode)

(defun kuro--arrow-up ()
  "Send arrow up key."
  (interactive)
  (kuro--send-key-sequence "\e[A" "\eOA"))

(defun kuro--arrow-down ()
  "Send arrow down key."
  (interactive)
  (kuro--send-key-sequence "\e[B" "\eOB"))

(defun kuro--arrow-left ()
  "Send arrow left key."
  (interactive)
  (kuro--send-key-sequence "\e[D" "\eOD"))

(defun kuro--arrow-right ()
  "Send arrow right key."
  (interactive)
  (kuro--send-key-sequence "\e[C" "\eOC"))


;;; Home/End/Page Keys

(defun kuro--HOME ()
  "Send Home key."
  (interactive)
  (kuro--send-key-sequence "\e[H" "\e[1~"))

(defun kuro--END ()
  "Send End key."
  (interactive)
  (kuro--send-key-sequence "\e[F" "\e[4~"))

(defun kuro--INSERT ()
  "Send Insert key."
  (interactive)
  (kuro--send-key-sequence "\e[2~" "\e[2~"))

(defun kuro--DELETE ()
  "Send Delete key."
  (interactive)
  (kuro--send-key-sequence "\e[3~" "\e[3~"))

(defun kuro--PAGE-UP ()
  "Send Page Up key."
  (interactive)
  (kuro--send-key-sequence "\e[5~" "\e[5~"))

(defun kuro--PAGE-DOWN ()
  "Send Page Down key."
  (interactive)
  (kuro--send-key-sequence "\e[6~" "\e[6~"))


;;; Function Keys F1-F12

(defun kuro--F1 ()  "Send F1 key."  (interactive) (kuro--send-key-sequence "\eOP"    "\eOP"))
(defun kuro--F2 ()  "Send F2 key."  (interactive) (kuro--send-key-sequence "\eOQ"    "\eOQ"))
(defun kuro--F3 ()  "Send F3 key."  (interactive) (kuro--send-key-sequence "\eOR"    "\eOR"))
(defun kuro--F4 ()  "Send F4 key."  (interactive) (kuro--send-key-sequence "\eOS"    "\eOS"))
(defun kuro--F5 ()  "Send F5 key."  (interactive) (kuro--send-key-sequence "\e[15~"  "\e[15~"))
(defun kuro--F6 ()  "Send F6 key."  (interactive) (kuro--send-key-sequence "\e[17~"  "\e[17~"))
(defun kuro--F7 ()  "Send F7 key."  (interactive) (kuro--send-key-sequence "\e[18~"  "\e[18~"))
(defun kuro--F8 ()  "Send F8 key."  (interactive) (kuro--send-key-sequence "\e[19~"  "\e[19~"))
(defun kuro--F9 ()  "Send F9 key."  (interactive) (kuro--send-key-sequence "\e[20~"  "\e[20~"))
(defun kuro--F10 () "Send F10 key." (interactive) (kuro--send-key-sequence "\e[21~"  "\e[21~"))
(defun kuro--F11 () "Send F11 key." (interactive) (kuro--send-key-sequence "\e[23~"  "\e[23~"))
(defun kuro--F12 () "Send F12 key." (interactive) (kuro--send-key-sequence "\e[24~"  "\e[24~"))


;;; Modifier Combinations

(defun kuro--ctrl-modified (char modifier)
  "Send Ctrl+CHAR.  MODIFIER is ignored (reserved for future use)."
  (interactive "nChar: \nModifier: ")
  (kuro--send-special (logand char 31)))

(defun kuro--alt-modified (char)
  "Send Alt+CHAR as ESC prefix followed by the character."
  (interactive "nChar: ")
  (kuro--send-char ?\e)
  (kuro--send-char char))

(defun kuro--ctrl-alt-modified (char modifier)
  "Send Ctrl+Alt+CHAR as ESC prefix followed by Ctrl-CHAR.  MODIFIER is ignored."
  (interactive "nChar: \nModifier: ")
  (kuro--send-char ?\e)
  (kuro--send-special (logand char 31)))


;;; Bracketed Paste Mode

(defvar kuro--bracketed-paste-mode nil
  "Non-nil when bracketed paste mode is active.")

(defun kuro--enable-bracketed-paste ()
  "Enable bracketed paste mode."
  (kuro--send-key "\e[200~")
  (setq kuro--bracketed-paste-mode t))

(defun kuro--disable-bracketed-paste ()
  "Disable bracketed paste mode."
  (kuro--send-key "\e[201~")
  (setq kuro--bracketed-paste-mode nil))


;;; Keymap Bindings

(defvar kuro--keymap
  (let ((map (make-sparse-keymap)))
    ;; Intercept all printable character input and forward to PTY
    (define-key map [remap self-insert-command] 'kuro--self-insert)
    ;; Special keys
    (define-key map [return]    'kuro--RET)
    (define-key map (kbd "C-m") 'kuro--RET)
    (define-key map [tab]       'kuro--TAB)
    (define-key map [backspace] 'kuro--DEL)
    ;; Arrow keys
    (define-key map [up]    'kuro--arrow-up)
    (define-key map [down]  'kuro--arrow-down)
    (define-key map [left]  'kuro--arrow-left)
    (define-key map [right] 'kuro--arrow-right)
    ;; Home/End/Page keys
    (define-key map [home]   'kuro--HOME)
    (define-key map [end]    'kuro--END)
    (define-key map [prior]  'kuro--PAGE-UP)
    (define-key map [next]   'kuro--PAGE-DOWN)
    (define-key map [delete] 'kuro--DELETE)
    (define-key map [insert] 'kuro--INSERT)
    ;; Function keys
    (define-key map [f1]  'kuro--F1)
    (define-key map [f2]  'kuro--F2)
    (define-key map [f3]  'kuro--F3)
    (define-key map [f4]  'kuro--F4)
    (define-key map [f5]  'kuro--F5)
    (define-key map [f6]  'kuro--F6)
    (define-key map [f7]  'kuro--F7)
    (define-key map [f8]  'kuro--F8)
    (define-key map [f9]  'kuro--F9)
    (define-key map [f10] 'kuro--F10)
    (define-key map [f11] 'kuro--F11)
    (define-key map [f12] 'kuro--F12)
    map)
  "Keymap for Kuro terminal emulator.")

(provide 'kuro-input)

;;; kuro-input.el ends here
