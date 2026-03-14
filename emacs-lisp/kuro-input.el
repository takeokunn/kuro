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

(defun kuro-scroll-up ()
  "Scroll back into terminal history by one screenful."
  (interactive)
  (when kuro--initialized
    (let ((lines (window-body-height)))
      (kuro--scroll-up lines)
      (setq kuro--scroll-offset (or (kuro--get-scroll-offset)
                                     (+ kuro--scroll-offset lines)))
      (kuro--render-cycle))))

(defun kuro-scroll-down ()
  "Scroll toward live terminal output by one screenful."
  (interactive)
  (when kuro--initialized
    (let ((lines (window-body-height)))
      (kuro--scroll-down lines)
      (setq kuro--scroll-offset (or (kuro--get-scroll-offset)
                                     (max 0 (- kuro--scroll-offset lines))))
      (kuro--render-cycle))))

(defun kuro-scroll-bottom ()
  "Return immediately to live terminal output."
  (interactive)
  (when kuro--initialized
    (kuro--scroll-down 999999)
    (setq kuro--scroll-offset (or (kuro--get-scroll-offset) 0))
    (kuro--render-cycle)))


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

(defvar-local kuro--bracketed-paste-mode nil
  "Cached bracketed paste mode state from Rust (?2004), polled by render cycle.")
(put 'kuro--bracketed-paste-mode 'permanent-local t)

(defvar-local kuro--keyboard-flags 0
  "Cached Kitty keyboard protocol flags, polled by render cycle.
This is a bitmask integer:
  Bit 0 (1): Disambiguate escape codes
  Bit 1 (2): Report event types (press/repeat/release)
  Bit 2 (4): Report alternate keys
  Bit 3 (8): Report all keys as escape codes
  Bit 4 (16): Report associated text")
(put 'kuro--keyboard-flags 'permanent-local t)

(defun kuro--sanitize-paste (text)
  "Sanitize TEXT before sending as bracketed paste.
Removes all ESC (\\x1b) bytes to prevent bracketed paste escape injection,
where clipboard content containing \\e[201~ could prematurely close the
paste bracket and cause command injection."
  (replace-regexp-in-string "\x1b" "" text))

(defun kuro--yank (&optional arg)
  "Yank from kill ring, wrapping with bracketed paste sequences when active."
  (interactive "*P")
  (let* ((n (if (numberp arg) (1- arg) 0))
         (text (current-kill n)))
    (if kuro--bracketed-paste-mode
        (kuro--send-key (concat "\e[200~" (kuro--sanitize-paste text) "\e[201~"))
      (kuro--send-key text))))

(defun kuro--yank-pop (&optional arg)
  "Cycle kill ring and yank, wrapping with bracketed paste sequences when active.
Like `yank-pop', signals an error if the previous command was not a yank."
  (interactive "p")
  (unless (memq last-command '(yank kuro--yank kuro--yank-pop))
    (user-error "Previous command was not a yank"))
  (let ((text (current-kill (or arg 1))))
    (if kuro--bracketed-paste-mode
        (kuro--send-key (concat "\e[200~" (kuro--sanitize-paste text) "\e[201~"))
      (kuro--send-key text))))


;;; Mouse Tracking

(defvar-local kuro--mouse-mode 0
  "Cached mouse tracking mode from Rust: 0=off, 1000/1002/1003=on.")
(put 'kuro--mouse-mode 'permanent-local t)

(defvar-local kuro--mouse-sgr nil
  "Cached mouse SGR extended coordinates modifier state from Rust.")
(put 'kuro--mouse-sgr 'permanent-local t)

(defun kuro--encode-mouse (event button press)
  "Encode mouse EVENT with BUTTON index as a PTY byte string.
BUTTON is 0=left, 1=middle, 2=right, 64=scroll-up, 65=scroll-down.
PRESS is non-nil for button press, nil for button release.
Returns the encoded string, or nil if mouse mode is off or position overflows."
  (when (> kuro--mouse-mode 0)
    (let* ((pos (event-start event))
           (col-row (posn-col-row pos))
           (col (car col-row))
           (row (cdr col-row))
           (col1 (1+ col))
           (row1 (1+ row)))
      (if kuro--mouse-sgr
          ;; SGR format: ESC[<btn;col;rowM (press) / ESC[<btn;col;rowm (release)
          (format "\e[<%d;%d;%d%s" button col1 row1 (if press "M" "m"))
        ;; X10 format: ESC[M{btn+32}{col+32}{row+32} — discard if out of range
        (when (and (< col 223) (< row 223))
          (let ((btn-byte (+ (if press button 3) 32)))
            (format "\e[M%c%c%c" btn-byte (+ col1 32) (+ row1 32))))))))

(defun kuro--encode-mouse-sgr (event button press)
  "Encode mouse EVENT in SGR format (used when kuro--mouse-sgr is set)."
  (let* ((pos (event-start event))
         (col-row (posn-col-row pos))
         (col1 (1+ (car col-row)))
         (row1 (1+ (cdr col-row))))
    (format "\e[<%d;%d;%d%s" button col1 row1 (if press "M" "m"))))

(defun kuro--mouse-press ()
  "Handle mouse button press and forward to PTY."
  (interactive)
  (when (> kuro--mouse-mode 0)
    (let* ((btn (pcase (event-basic-type last-input-event)
                  ('mouse-1 0) ('mouse-2 1) ('mouse-3 2) (_ nil)))
           (seq (when btn
                  (if kuro--mouse-sgr
                      (kuro--encode-mouse-sgr last-input-event btn t)
                    (kuro--encode-mouse last-input-event btn t)))))
      (when seq (kuro--send-key seq)))))

(defun kuro--mouse-release ()
  "Handle mouse button release and forward to PTY."
  (interactive)
  (when (> kuro--mouse-mode 0)
    (let* ((btn (pcase (event-basic-type last-input-event)
                  ('mouse-1 0) ('mouse-2 1) ('mouse-3 2) (_ nil)))
           (seq (when btn
                  (if kuro--mouse-sgr
                      (kuro--encode-mouse-sgr last-input-event btn nil)
                    (kuro--encode-mouse last-input-event btn nil)))))
      (when seq (kuro--send-key seq)))))

(defun kuro--mouse-scroll-up ()
  "Handle scroll-up mouse event and forward to PTY."
  (interactive)
  (when (> kuro--mouse-mode 0)
    (let ((seq (if kuro--mouse-sgr
                   (kuro--encode-mouse-sgr last-input-event 64 t)
                 (kuro--encode-mouse last-input-event 64 t))))
      (when seq (kuro--send-key seq)))))

(defun kuro--mouse-scroll-down ()
  "Handle scroll-down mouse event and forward to PTY."
  (interactive)
  (when (> kuro--mouse-mode 0)
    (let ((seq (if kuro--mouse-sgr
                   (kuro--encode-mouse-sgr last-input-event 65 t)
                 (kuro--encode-mouse last-input-event 65 t))))
      (when seq (kuro--send-key seq)))))


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
    ;; Scrollback viewport navigation (Shift+PgUp/PgDn/End)
    (define-key map [S-prior] #'kuro-scroll-up)
    (define-key map [S-next]  #'kuro-scroll-down)
    (define-key map [S-end]   #'kuro-scroll-bottom)
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
    ;; Mouse tracking (forwarded to PTY when mouse mode is active)
    (define-key map [down-mouse-1] 'kuro--mouse-press)
    (define-key map [down-mouse-2] 'kuro--mouse-press)
    (define-key map [down-mouse-3] 'kuro--mouse-press)
    (define-key map [mouse-1]      'kuro--mouse-release)
    (define-key map [mouse-2]      'kuro--mouse-release)
    (define-key map [mouse-3]      'kuro--mouse-release)
    (define-key map [mouse-4]      'kuro--mouse-scroll-up)
    (define-key map [mouse-5]      'kuro--mouse-scroll-down)
    ;; Yank remaps (bracketed paste aware)
    (define-key map [remap yank]     #'kuro--yank)
    (define-key map [remap yank-pop] #'kuro--yank-pop)
    ;; Ctrl+letter keys (C-a through C-z, excluding C-c prefix key)
    ;; Under lexical-binding, each let* iteration creates a fresh binding of `byte`,
    ;; so each lambda captures a distinct value.  The inner (let ((b byte)) ...) is a
    ;; belt-and-suspenders guard that would matter under dynamic binding but is not
    ;; strictly necessary here.
    (dotimes (i 26)
      (let* ((char (+ ?a i))
             (byte (logand char 31)))
        (unless (= char ?c)                  ; C-c is a prefix key in kuro-mode-map
          (define-key map (vector (list 'control char))
            (let ((b byte))
              (lambda () (interactive) (kuro--send-special b)))))))
    ;; Ensure event-symbol bindings win over the loop's character-code bindings.
    ;; In GUI Emacs, [backspace]/[tab]/[return] are distinct from [C-h]/[C-i]/[C-m].
    (define-key map [backspace] #'kuro--DEL)
    (define-key map [tab]       #'kuro--TAB)
    (define-key map [return]    #'kuro--RET)
    ;; Alt+letter: M-a through M-z (for systems where Option/Alt is the Meta key)
    (dotimes (i 26)
      (let ((char (+ ?a i)))
        (define-key map (vector (list 'meta char))
          (let ((c char))
            (lambda () (interactive) (kuro--send-char ?\e) (kuro--send-char c))))))
    ;; ESC+letter two-key fallback (for macOS where Option sends ESC prefix, not Meta)
    (dotimes (i 26)
      (let ((char (+ ?a i)))
        (define-key map (kbd (format "ESC %c" char))
          (let ((c char))
            (lambda () (interactive) (kuro--send-char ?\e) (kuro--send-char c))))))
    ;; Modifier+arrow keys — xterm CSI 1;Pm sequences (Shift=2, Alt=3, Ctrl=5)
    (define-key map [S-up]    (lambda () (interactive) (kuro--send-key "\e[1;2A")))
    (define-key map [M-up]    (lambda () (interactive) (kuro--send-key "\e[1;3A")))
    (define-key map [C-up]    (lambda () (interactive) (kuro--send-key "\e[1;5A")))
    (define-key map [S-down]  (lambda () (interactive) (kuro--send-key "\e[1;2B")))
    (define-key map [M-down]  (lambda () (interactive) (kuro--send-key "\e[1;3B")))
    (define-key map [C-down]  (lambda () (interactive) (kuro--send-key "\e[1;5B")))
    (define-key map [S-right] (lambda () (interactive) (kuro--send-key "\e[1;2C")))
    (define-key map [M-right] (lambda () (interactive) (kuro--send-key "\e[1;3C")))
    (define-key map [C-right] (lambda () (interactive) (kuro--send-key "\e[1;5C")))
    (define-key map [S-left]  (lambda () (interactive) (kuro--send-key "\e[1;2D")))
    (define-key map [M-left]  (lambda () (interactive) (kuro--send-key "\e[1;3D")))
    (define-key map [C-left]  (lambda () (interactive) (kuro--send-key "\e[1;5D")))
    map)
  "Keymap for Kuro terminal emulator.")

;;; Kitty Keyboard Protocol

(defun kuro--encode-kitty-key (key modifiers)
  "Encode KEY with MODIFIERS in Kitty keyboard protocol format.
KEY is a Unicode codepoint integer.
MODIFIERS is a bitmask: shift=1, alt=2, ctrl=4, super=8, hyper=16, meta=32.
Returns the encoded escape sequence string."
  (if (= modifiers 0)
      (format "\e[%du" key)
    (format "\e[%d;%du" key (1+ modifiers))))

(provide 'kuro-input)

;;; kuro-input.el ends here
