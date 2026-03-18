;;; kuro-input.el --- Keyboard input handling for Kuro terminal emulator -*- lexical-binding: t -*-

;;; Commentary:

;; This module provides keyboard input handling for the Kuro terminal emulator.
;; It handles printable characters, special keys, arrow keys (in normal and
;; application modes), function keys, modifier combinations, and bracketed paste
;; mode.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)

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

(defcustom kuro-input-echo-delay 0.01
  "Seconds to wait after a keypress before polling for the PTY echo response.
The PTY reader thread needs a short window to receive the shell's echo and
deposit it in the crossbeam channel before the Emacs side polls.  A 0 s
delay is too aggressive on most systems: the idle timer fires before the
reader thread wakes from its blocking read call, resulting in an empty poll
and no cursor movement until the next 60 fps periodic tick (~16 ms later).

10 ms (0.01 s) comfortably covers the PTY kernel round-trip on both macOS
and Linux without adding perceptible latency to keystroke echo."
  :type 'float
  :group 'kuro)

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
;; Note: kuro--send-special already calls kuro--schedule-immediate-render.

(defun kuro--alt-modified (char)
  "Send Alt+CHAR as ESC prefix followed by the character."
  (interactive "nChar: ")
  (kuro--send-key (string ?\e char))
  (kuro--schedule-immediate-render))

(defun kuro--ctrl-alt-modified (char modifier)
  "Send Ctrl+Alt+CHAR as ESC prefix followed by Ctrl-CHAR.  MODIFIER is ignored."
  (interactive "nChar: \nModifier: ")
  (kuro--send-key (concat (string ?\e) (string (logand char 31))))
  (kuro--schedule-immediate-render))


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
      (kuro--send-key text)))
  (kuro--schedule-immediate-render))

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

(defvar-local kuro--mouse-pixel-mode nil
  "Cached mouse pixel coordinate mode (?1016) state from Rust.
When non-nil, mouse positions are reported in pixels instead of cells.")
(put 'kuro--mouse-pixel-mode 'permanent-local t)

(defun kuro--encode-mouse (event button press)
  "Encode mouse EVENT with BUTTON index as a PTY byte string.
BUTTON is 0=left, 1=middle, 2=right, 64=scroll-up, 65=scroll-down.
PRESS is non-nil for button press, nil for button release.
Returns the encoded string, or nil if mouse mode is off or position overflows."
  (when (> kuro--mouse-mode 0)
    (let* ((pos (event-start event))
           (col-row (if kuro--mouse-pixel-mode
                        ;; Pixel mode: report pixel coordinates
                        (let ((xy (posn-x-y pos)))
                          (cons (or (car xy) 0) (or (cdr xy) 0)))
                      ;; Cell mode: report 1-based cell coordinates
                      (let ((cr (posn-col-row pos)))
                        (cons (1+ (car cr)) (1+ (cdr cr))))))
           (col1 (car col-row))
           (row1 (cdr col-row)))
      (if (or kuro--mouse-sgr kuro--mouse-pixel-mode)
          ;; SGR pixel format: ESC[<btn;px;pyM/m
          (format "\e[<%d;%d;%d%s" button col1 row1 (if press "M" "m"))
        ;; X10 format: ESC[M{btn+32}{col+32}{row+32} — discard if out of range
        (when (and (< col1 224) (< row1 224))
          (let ((btn-byte (+ (if press button 3) 32)))
            (format "\e[M%c%c%c" btn-byte (+ col1 32) (+ row1 32))))))))

(defun kuro--encode-mouse-sgr (event button press)
  "Encode mouse EVENT in SGR format (used when kuro--mouse-sgr is set)."
  (let* ((pos (event-start event))
         (col-row (if kuro--mouse-pixel-mode
                      ;; Pixel mode
                      (let ((xy (posn-x-y pos)))
                        (cons (or (car xy) 0) (or (cdr xy) 0)))
                    (let ((cr (posn-col-row pos)))
                      (cons (1+ (car cr)) (1+ (cdr cr))))))
         (col1 (car col-row))
         (row1 (cdr col-row)))
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

;; Helper macros for sending control and escape sequences.
;; These are used inside the keymap definition below.
(defun kuro--send-ctrl (byte)
  "Send a single control byte (0–31 or 127) to the PTY and schedule render."
  (kuro--send-key (string byte))
  (kuro--schedule-immediate-render))

(defun kuro--send-meta (char)
  "Send ESC + CHAR to the PTY (readline Alt/Meta prefix) and schedule render."
  (kuro--send-key (string ?\e char))
  (kuro--schedule-immediate-render))

(defun kuro--keymap-exception-p (key)
  "Return non-nil if KEY string is listed in `kuro-keymap-exceptions'."
  (and (boundp 'kuro-keymap-exceptions)
       (member key kuro-keymap-exceptions)))

(defvar kuro--keymap nil
  "Keymap for Kuro terminal emulator.  Built by `kuro--build-keymap'.")

(defun kuro--build-keymap ()
  "Build and return the Kuro terminal input keymap.
Keys listed in `kuro-keymap-exceptions' are omitted so they fall through
to the standard Emacs global keymap.  Also stores the result in
`kuro--keymap' for use as the parent of `kuro-mode-map'."
  (let ((map (make-sparse-keymap)))
    ;; ── Printable characters ──────────────────────────────────────────────────
    ;; Intercept all printable character input and forward to PTY.
    (define-key map [remap self-insert-command] #'kuro--self-insert)

    ;; ── Special / whitespace keys ─────────────────────────────────────────────
    ;; [return] and (kbd "C-m") are both ?\r (ASCII 13) in terminal semantics.
    ;; [tab] and (kbd "C-i") are both ?\t.
    ;; [backspace] is DEL (127); (kbd "C-h") is BS (8) — both must work.
    (define-key map [return]    #'kuro--RET)
    (define-key map (kbd "C-m") #'kuro--RET)
    (define-key map [tab]       #'kuro--TAB)
    (define-key map (kbd "C-i") #'kuro--TAB)
    (define-key map [backspace] #'kuro--DEL)
    ;; C-h must also send DEL (127) — in terminals, backspace sends 127 and C-h
    ;; also traditionally sends 127 (or 8 depending on stty).  Sending 127 is
    ;; the modern default that matches xterm/kitty.
    (define-key map (kbd "C-h") #'kuro--DEL)

    ;; ── Ctrl+letter: ALL C-a … C-z sent as raw control bytes ─────────────────
    ;;
    ;; IMPORTANT: (vector (list 'control ?b)) is NOT the same key descriptor as
    ;; (kbd "C-b") in GUI Emacs.  We must use (kbd "C-x") / [?\C-x] forms so
    ;; that Emacs resolves the event correctly and this binding wins over
    ;; global-map entries like `backward-char' (C-b), `forward-char' (C-f), etc.
    ;;
    ;; C-c is handled specially: kuro-mode-map defines C-c as a prefix (C-c C-c
    ;; = SIGINT, etc.).  Binding C-c here as a raw byte would shadow that prefix.
    ;; We therefore keep C-c as the meta-prefix in kuro-mode-map and bind
    ;; "C-c C-c" there to send ^C.

    ;; C-a (^A, 1) — readline: move to beginning of line
    (define-key map (kbd "C-a") (lambda () (interactive) (kuro--send-ctrl 1)))
    ;; C-b (^B, 2) — readline: move cursor left
    (define-key map (kbd "C-b") (lambda () (interactive) (kuro--send-ctrl 2)))
    ;; C-d (^D, 4) — readline: delete char / EOF
    (define-key map (kbd "C-d") (lambda () (interactive) (kuro--send-ctrl 4)))
    ;; C-e (^E, 5) — readline: move to end of line
    (define-key map (kbd "C-e") (lambda () (interactive) (kuro--send-ctrl 5)))
    ;; C-f (^F, 6) — readline: move cursor right
    (define-key map (kbd "C-f") (lambda () (interactive) (kuro--send-ctrl 6)))
    ;; C-g (^G, 7) — readline: abort / bell
    (define-key map (kbd "C-g") (lambda () (interactive) (kuro--send-ctrl 7)))
    ;; C-k (^K, 11) — readline: kill to end of line
    (define-key map (kbd "C-k") (lambda () (interactive) (kuro--send-ctrl 11)))
    ;; C-l (^L, 12) — readline/shell: clear screen
    (define-key map (kbd "C-l") (lambda () (interactive) (kuro--send-ctrl 12)))
    ;; C-n (^N, 14) — readline: next history entry
    (define-key map (kbd "C-n") (lambda () (interactive) (kuro--send-ctrl 14)))
    ;; C-o (^O, 15) — readline: operate-and-get-next
    (define-key map (kbd "C-o") (lambda () (interactive) (kuro--send-ctrl 15)))
    ;; C-p (^P, 16) — readline: previous history entry
    (define-key map (kbd "C-p") (lambda () (interactive) (kuro--send-ctrl 16)))
    ;; C-q (^Q, 17) — XON / readline: quoted-insert
    (define-key map (kbd "C-q") (lambda () (interactive) (kuro--send-ctrl 17)))
    ;; C-r (^R, 18) — readline: reverse incremental search
    (define-key map (kbd "C-r") (lambda () (interactive) (kuro--send-ctrl 18)))
    ;; C-s (^S, 19) — XOFF / readline: forward incremental search
    (define-key map (kbd "C-s") (lambda () (interactive) (kuro--send-ctrl 19)))
    ;; C-t (^T, 20) — readline: transpose chars
    (define-key map (kbd "C-t") (lambda () (interactive) (kuro--send-ctrl 20)))
    ;; C-u (^U, 21) — readline: kill whole line
    (define-key map (kbd "C-u") (lambda () (interactive) (kuro--send-ctrl 21)))
    ;; C-v (^V, 22) — readline: quoted-insert / literal next
    (define-key map (kbd "C-v") (lambda () (interactive) (kuro--send-ctrl 22)))
    ;; C-w (^W, 23) — readline: kill word backwards
    (define-key map (kbd "C-w") (lambda () (interactive) (kuro--send-ctrl 23)))
    ;; C-x (^X, 24) — readline prefix (C-x C-e, C-x C-r, etc.)
    ;; Bind C-x as a raw byte so it reaches readline; 2-key readline sequences
    ;; (e.g. C-x C-e = edit-and-execute) will work because readline receives
    ;; both bytes in sequence.
    (define-key map (kbd "C-x") (lambda () (interactive) (kuro--send-ctrl 24)))
    ;; C-y (^Y, 25) — readline: yank (paste kill-ring)
    ;; Note: kuro--yank is remapped below for bracketed-paste support.
    ;; C-y as raw byte fallback (when not using Emacs yank remap):
    (define-key map (kbd "C-y") (lambda () (interactive) (kuro--send-ctrl 25)))
    ;; C-z (^Z, 26) — SIGTSTP (suspend)
    (define-key map (kbd "C-z") (lambda () (interactive) (kuro--send-ctrl 26)))
    ;; ESC — sent by pressing the Escape key.
    ;; Use [escape] (the symbolic event), not (kbd "ESC"), because (kbd "ESC")
    ;; registers ESC as a prefix key that shadows all two-key ESC+x sequences.
    (define-key map [escape] (lambda () (interactive) (kuro--send-ctrl 27)))
    ;; C-\ (^\, 28) — SIGQUIT
    (define-key map (kbd "C-\\") (lambda () (interactive) (kuro--send-ctrl 28)))
    ;; C-] (^], 29) — telnet escape / readline: character search
    (define-key map (kbd "C-]") (lambda () (interactive) (kuro--send-ctrl 29)))
    ;; C-_ (^_, 31) — readline: undo
    (define-key map (kbd "C-_") (lambda () (interactive) (kuro--send-ctrl 31)))
    ;; DEL (127) — same as [backspace]; some terminals send this for C-?
    (define-key map (kbd "DEL") #'kuro--DEL)

    ;; ── Alt/Meta+letter: M-a … M-z → ESC + letter ───────────────────────────
    ;;
    ;; In readline, Alt+key is sent as ESC then the key character.  These are
    ;; the bash readline Alt bindings most frequently used:
    ;;   M-b  — move word left
    ;;   M-f  — move word right
    ;;   M-d  — delete word forward
    ;;   M-DEL — delete word backward
    ;;   M-.  — insert last argument of previous command (yank-last-arg)
    ;;   M-r  — revert-line (restore original line)
    ;;   M-u  — uppercase word
    ;;   M-l  — lowercase word
    ;;   M-c  — capitalize word
    ;;   M-t  — transpose words
    ;;   M-y  — yank-pop (cycle through kill ring)
    ;;   M-<  — beginning of history
    ;;   M->  — end of history
    ;;   M-?  — possible completions
    ;;   M-/  — complete filename
    ;;
    ;; (vector (list 'meta char)) is NOT equivalent to (kbd "M-b") in GUI Emacs,
    ;; so we use explicit (kbd "M-x") descriptors for the most important keys,
    ;; plus a loop for the full alphabet.

    ;; Alt/Meta+letter: bind ALL M-a … M-z, M-A … M-Z, M-0 … M-9 first via loop,
    ;; then override the most-important ones explicitly.
    ;;
    ;; Use (kbd (format "M-%c" char)) — this produces the correct event descriptor
    ;; in both terminal and GUI Emacs.  (vector (list 'meta char)) is NOT equivalent
    ;; and would be silently ignored in GUI frames.
    ;;
    ;; The loop runs FIRST so that explicit overrides below take precedence.
    (dolist (char (append (number-sequence ?a ?z) (number-sequence ?A ?Z)
                          (number-sequence ?0 ?9)))
      (let ((c char))
        (define-key map (kbd (format "M-%c" c))
          (lambda () (interactive) (kuro--send-meta c)))))

    ;; ESC + letter two-key fallback (macOS: Option key sends ESC prefix, not Meta).
    ;; We cannot use (kbd "ESC %c") after [escape] is bound as a single key,
    ;; so we use the raw two-character vector form instead: [\e ?x].
    ;; This registers "ESC followed by letter" as a distinct two-event sequence.
    (dolist (char (append (number-sequence ?a ?z) (number-sequence ?A ?Z)))
      (let ((c char))
        (define-key map (vector ?\e c)
          (lambda () (interactive) (kuro--send-meta c)))))

    ;; Most-used readline Alt bindings — explicit for documentation clarity.
    ;; These re-define the same keys the loop above set, which is fine.
    (define-key map (kbd "M-b")   (lambda () (interactive) (kuro--send-meta ?b)))
    (define-key map (kbd "M-f")   (lambda () (interactive) (kuro--send-meta ?f)))
    (define-key map (kbd "M-d")   (lambda () (interactive) (kuro--send-meta ?d)))
    (define-key map (kbd "M-.")   (lambda () (interactive) (kuro--send-meta ?.)))
    (define-key map (kbd "M-r")   (lambda () (interactive) (kuro--send-meta ?r)))
    (define-key map (kbd "M-u")   (lambda () (interactive) (kuro--send-meta ?u)))
    (define-key map (kbd "M-l")   (lambda () (interactive) (kuro--send-meta ?l)))
    (define-key map (kbd "M-c")   (lambda () (interactive) (kuro--send-meta ?c)))
    (define-key map (kbd "M-t")   (lambda () (interactive) (kuro--send-meta ?t)))
    (define-key map (kbd "M-y")   (lambda () (interactive) (kuro--send-meta ?y)))
    (define-key map (kbd "M-<")   (lambda () (interactive) (kuro--send-meta ?<)))
    (define-key map (kbd "M->")   (lambda () (interactive) (kuro--send-meta ?>)))
    (define-key map (kbd "M-?")   (lambda () (interactive) (kuro--send-meta ??)))
    (define-key map (kbd "M-/")   (lambda () (interactive) (kuro--send-meta ?/)))
    (define-key map (kbd "M-_")   (lambda () (interactive) (kuro--send-meta ?_)))
    ;; M-DEL — delete word backward (sends ESC + DEL = ESC + 127)
    (define-key map (kbd "M-DEL")
      (lambda () (interactive) (kuro--send-key (string ?\e ?\x7f))
        (kuro--schedule-immediate-render)))
    ;; M-<backspace> — same as M-DEL on many keyboards
    (define-key map (kbd "M-<backspace>")
      (lambda () (interactive) (kuro--send-key (string ?\e ?\x7f))
        (kuro--schedule-immediate-render)))

    ;; ── Arrow keys ────────────────────────────────────────────────────────────
    (define-key map [up]    #'kuro--arrow-up)
    (define-key map [down]  #'kuro--arrow-down)
    (define-key map [left]  #'kuro--arrow-left)
    (define-key map [right] #'kuro--arrow-right)

    ;; ── Home / End / Page / Insert / Delete ───────────────────────────────────
    (define-key map [home]   #'kuro--HOME)
    (define-key map [end]    #'kuro--END)
    (define-key map [prior]  #'kuro--PAGE-UP)
    (define-key map [next]   #'kuro--PAGE-DOWN)
    (define-key map [delete] #'kuro--DELETE)
    (define-key map [insert] #'kuro--INSERT)

    ;; ── Scrollback viewport (Shift+PgUp / PgDn / End) ────────────────────────
    (define-key map [S-prior] #'kuro-scroll-up)
    (define-key map [S-next]  #'kuro-scroll-down)
    (define-key map [S-end]   #'kuro-scroll-bottom)

    ;; ── Function keys F1–F12 ──────────────────────────────────────────────────
    (define-key map [f1]  #'kuro--F1)
    (define-key map [f2]  #'kuro--F2)
    (define-key map [f3]  #'kuro--F3)
    (define-key map [f4]  #'kuro--F4)
    (define-key map [f5]  #'kuro--F5)
    (define-key map [f6]  #'kuro--F6)
    (define-key map [f7]  #'kuro--F7)
    (define-key map [f8]  #'kuro--F8)
    (define-key map [f9]  #'kuro--F9)
    (define-key map [f10] #'kuro--F10)
    (define-key map [f11] #'kuro--F11)
    (define-key map [f12] #'kuro--F12)

    ;; ── Modifier + arrow keys (xterm CSI 1;Pm sequences) ─────────────────────
    ;; Shift=2, Alt=3, Ctrl=5
    (define-key map [S-up]    (lambda () (interactive) (kuro--send-key "\e[1;2A") (kuro--schedule-immediate-render)))
    (define-key map [M-up]    (lambda () (interactive) (kuro--send-key "\e[1;3A") (kuro--schedule-immediate-render)))
    (define-key map [C-up]    (lambda () (interactive) (kuro--send-key "\e[1;5A") (kuro--schedule-immediate-render)))
    (define-key map [S-down]  (lambda () (interactive) (kuro--send-key "\e[1;2B") (kuro--schedule-immediate-render)))
    (define-key map [M-down]  (lambda () (interactive) (kuro--send-key "\e[1;3B") (kuro--schedule-immediate-render)))
    (define-key map [C-down]  (lambda () (interactive) (kuro--send-key "\e[1;5B") (kuro--schedule-immediate-render)))
    (define-key map [S-right] (lambda () (interactive) (kuro--send-key "\e[1;2C") (kuro--schedule-immediate-render)))
    (define-key map [M-right] (lambda () (interactive) (kuro--send-key "\e[1;3C") (kuro--schedule-immediate-render)))
    (define-key map [C-right] (lambda () (interactive) (kuro--send-key "\e[1;5C") (kuro--schedule-immediate-render)))
    (define-key map [S-left]  (lambda () (interactive) (kuro--send-key "\e[1;2D") (kuro--schedule-immediate-render)))
    (define-key map [M-left]  (lambda () (interactive) (kuro--send-key "\e[1;3D") (kuro--schedule-immediate-render)))
    (define-key map [C-left]  (lambda () (interactive) (kuro--send-key "\e[1;5D") (kuro--schedule-immediate-render)))

    ;; ── Mouse tracking ────────────────────────────────────────────────────────
    (define-key map [down-mouse-1] #'kuro--mouse-press)
    (define-key map [down-mouse-2] #'kuro--mouse-press)
    (define-key map [down-mouse-3] #'kuro--mouse-press)
    (define-key map [mouse-1]      #'kuro--mouse-release)
    (define-key map [mouse-2]      #'kuro--mouse-release)
    (define-key map [mouse-3]      #'kuro--mouse-release)
    (define-key map [mouse-4]      #'kuro--mouse-scroll-up)
    (define-key map [mouse-5]      #'kuro--mouse-scroll-down)

    ;; ── Yank (bracketed-paste aware) ─────────────────────────────────────────
    (define-key map [remap yank]     #'kuro--yank)
    (define-key map [remap yank-pop] #'kuro--yank-pop)

    ;; Remove bindings for keys listed in kuro-keymap-exceptions so they fall
    ;; through to the standard Emacs global keymap (e.g. M-x, C-g, C-x).
    (dolist (exc (bound-and-true-p kuro-keymap-exceptions))
      (condition-case nil
          (progn
            (define-key map (kbd exc) nil)
            ;; For M-* keys also clear the ESC+char two-key fallback used on
            ;; macOS where the Option key sends an ESC prefix instead of Meta.
            (when (string-prefix-p "M-" exc)
              (let* ((rest (substring exc 2))
                     (char (and (= (length rest) 1) (aref rest 0))))
                (when char
                  (define-key map (vector ?\e char) nil)))))
        (error nil)))
    (setq kuro--keymap map)
    map))

;;; Keymap initialization

;; Build kuro--keymap at load time so it is available immediately for tests
;; and for any kuro-mode buffer that calls (set-keymap-parent kuro-mode-map kuro--keymap).
(kuro--build-keymap)


;;; kuro-send-next-key — bypass keymap exceptions

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
    (format "\e[%d;%du" key (1+ modifiers))))

(provide 'kuro-input)

;;; kuro-input.el ends here
