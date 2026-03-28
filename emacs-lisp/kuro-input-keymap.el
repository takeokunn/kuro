;;; kuro-input-keymap.el --- Terminal input keymap for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Builds the kuro--keymap used as parent of kuro-mode-map.
;; Organized into per-category helper functions for maintainability.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-input-mouse)
(require 'kuro-input-paste)

;; Forward references: these functions are defined in kuro-input.el, which is
;; loaded before kuro-input-keymap.el at runtime.  declare-function silences
;; byte-compiler warnings without introducing a circular require.
(declare-function kuro--self-insert "kuro-input" ())
(declare-function kuro--RET "kuro-input" ())
(declare-function kuro--TAB "kuro-input" ())
(declare-function kuro--DEL "kuro-input" ())
(declare-function kuro--arrow-up "kuro-input" ())
(declare-function kuro--arrow-down "kuro-input" ())
(declare-function kuro--arrow-left "kuro-input" ())
(declare-function kuro--arrow-right "kuro-input" ())
(declare-function kuro--HOME "kuro-input" ())
(declare-function kuro--END "kuro-input" ())
(declare-function kuro--INSERT "kuro-input" ())
(declare-function kuro--DELETE "kuro-input" ())
(declare-function kuro--PAGE-UP "kuro-input" ())
(declare-function kuro--PAGE-DOWN "kuro-input" ())
(declare-function kuro-scroll-up "kuro-input" ())
(declare-function kuro-scroll-down "kuro-input" ())
(declare-function kuro-scroll-bottom "kuro-input" ())
(declare-function kuro--F1 "kuro-input" ())
(declare-function kuro--F2 "kuro-input" ())
(declare-function kuro--F3 "kuro-input" ())
(declare-function kuro--F4 "kuro-input" ())
(declare-function kuro--F5 "kuro-input" ())
(declare-function kuro--F6 "kuro-input" ())
(declare-function kuro--F7 "kuro-input" ())
(declare-function kuro--F8 "kuro-input" ())
(declare-function kuro--F9 "kuro-input" ())
(declare-function kuro--F10 "kuro-input" ())
(declare-function kuro--F11 "kuro-input" ())
(declare-function kuro--F12 "kuro-input" ())
(declare-function kuro--send-ctrl "kuro-input" (byte))
(declare-function kuro--send-key  "kuro-ffi"   (key))
(declare-function kuro--send-meta "kuro-input" (char))
(declare-function kuro--schedule-immediate-render "kuro-input" ())
(declare-function kuro--scroll-aware-ctrl-v "kuro-input" ())
(declare-function kuro--scroll-aware-meta-v "kuro-input" ())


;;; Keymap Variable

(defvar kuro--keymap nil
  "Keymap for Kuro terminal emulator.  Built by `kuro--build-keymap'.")


;;; Keymap Helper Functions

(defun kuro--keymap-setup-special (map)
  "Add special key bindings to MAP (RET, TAB, DEL, escape, Ctrl variants)."
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
  ;; DEL (127) — same as [backspace]; some terminals send this for C-?
  (define-key map (kbd "DEL") #'kuro--DEL))

(defconst kuro--ctrl-key-table
  ;; (KBD-STRING . CTRL-BYTE): CTRL-BYTE = ASCII code 1-31.
  ;; C-c is reserved as the kuro-mode-map prefix key and is intentionally absent.
  '(("C-a"  .  1) ("C-b"  .  2)
    ("C-d"  .  4) ("C-e"  .  5) ("C-f"  .  6) ("C-g"  .  7)
    ("C-k"  . 11) ("C-l"  . 12) ("C-n"  . 14) ("C-o"  . 15)
    ("C-p"  . 16) ("C-q"  . 17) ("C-r"  . 18) ("C-s"  . 19)
    ("C-t"  . 20) ("C-u"  . 21)               ("C-w"  . 23)
    ("C-x"  . 24) ("C-y"  . 25) ("C-z"  . 26)
    ("C-\\" . 28) ("C-]"  . 29) ("C-_"  . 31))
  "Mapping of Emacs Ctrl+key strings to their ASCII control-byte values.
Each entry is (KBD-STRING . CTRL-BYTE).  The ctrl byte for a letter is
\\(logand char 31\\): C-a=1, C-b=2, ..., C-z=26.
C-c is intentionally absent — it is the kuro-mode-map prefix key.")

(defun kuro--keymap-setup-ctrl (map)
  "Add Ctrl+letter bindings to MAP, forwarding each to the PTY as its control byte.
Uses `kuro--ctrl-key-table' to map Emacs key strings to ASCII control codes."
  (dolist (entry kuro--ctrl-key-table)
    (let ((key  (car entry))
          (byte (cdr entry)))
      (define-key map (kbd key)
        (lambda () (interactive) (kuro--send-ctrl byte)))))
  ;; C-v: scroll-aware — scrolls when in scrollback, sends ctrl byte when at live view.
  (define-key map (kbd "C-v") #'kuro--scroll-aware-ctrl-v)
  ;; ESC must use [escape] (not kbd "ESC") to avoid shadowing all ESC-prefixed bindings.
  (define-key map [escape] (lambda () (interactive) (kuro--send-ctrl 27))))

(defun kuro--send-meta-backspace ()
  "Send ESC+DEL (Meta-Backspace) to the PTY.
This is the standard control sequence for backward-kill-word in readline/bash."
  (interactive)
  (kuro--send-key (string ?\e ?\x7f))
  (kuro--schedule-immediate-render))

(defconst kuro--meta-punct-bindings
  '(("M-." . ?.) ("M-<" . ?<) ("M->" . ?>)
    ("M-?" . ??) ("M-/" . ?/) ("M-_" . ?_))
  "Alist of (KBD-STRING . CHAR) for Meta+punctuation bindings.
Each entry maps an Emacs key string to the character sent via `kuro--send-meta'.
Applied by `kuro--keymap-setup-meta'.
M-DEL and M-<backspace> are handled separately (they call `kuro--send-meta-backspace').")

(defun kuro--keymap-setup-meta (map)
  "Add Meta/Alt bindings M-a through M-z and related keys to MAP.

In readline, Alt+key is sent as ESC then the key character.  These are
the bash readline Alt bindings most frequently used:
  M-b  — move word left          M-f  — move word right
  M-d  — delete word forward     M-DEL — delete word backward
  M-.  — insert last argument    M-r  — revert-line
  M-u  — uppercase word          M-l  — lowercase word
  M-c  — capitalize word         M-t  — transpose words
  M-y  — yank-pop                M-<  — beginning of history
  M->  — end of history          M-?  — possible completions
  M-/  — complete filename

The loop runs FIRST so that explicit overrides below take precedence.
Use (kbd (format \"M-%c\" char)) — this produces the correct event descriptor
in both terminal and GUI Emacs.  (vector (list 'meta char)) is NOT equivalent
and would be silently ignored in GUI frames."
  ;; Bind ALL M-a … M-z, M-A … M-Z, M-0 … M-9 via loop.
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

  ;; Keys outside the a-z/A-Z/0-9 ranges — not covered by the dolist above.
  (dolist (entry kuro--meta-punct-bindings)
    (let ((c (cdr entry)))
      (define-key map (kbd (car entry))
        (lambda () (interactive) (kuro--send-meta c)))))
  ;; M-v: scroll-aware — scrolls when in scrollback, sends ESC+v when at live view.
  (define-key map (kbd "M-v") #'kuro--scroll-aware-meta-v)
  (define-key map (vector ?\e ?v) #'kuro--scroll-aware-meta-v)
  ;; M-DEL — delete word backward (sends ESC + DEL = ESC + 127)
  (define-key map (kbd "M-DEL")        #'kuro--send-meta-backspace)
  ;; M-<backspace> — same as M-DEL on many keyboards
  (define-key map (kbd "M-<backspace>") #'kuro--send-meta-backspace))

(defconst kuro--xterm-modifier-codes
  '((S . 2) (M . 3) (C . 5))
  "xterm CSI modifier parameter codes used in \\e[1;Nm sequences.
Shift=2, Alt/Meta=3, Ctrl=5.  Note: code 4 (Shift+Alt) is absent here
because Emacs does not generate a distinct [S-M-up] event.")

(defconst kuro--xterm-arrow-codes
  '((up . ?A) (down . ?B) (right . ?C) (left . ?D))
  "xterm CSI final-byte characters for arrow directions in \\e[1;Nm sequences.
The letters A/B/C/D are the original VT100 cursor movement codes (CUU/CUD/CUF/CUB).
Used with `kuro--xterm-modifier-codes' to build the 12 modifier+arrow sequences
like \\e[1;2A (Shift+Up), \\e[1;5C (Ctrl+Right), etc.")

(defconst kuro--fkey-handlers
  '((f1  . kuro--F1)  (f2  . kuro--F2)  (f3  . kuro--F3)  (f4  . kuro--F4)
    (f5  . kuro--F5)  (f6  . kuro--F6)  (f7  . kuro--F7)  (f8  . kuro--F8)
    (f9  . kuro--F9)  (f10 . kuro--F10) (f11 . kuro--F11) (f12 . kuro--F12))
  "Alist mapping Emacs function-key event symbols to their Kuro handler commands.")

(defconst kuro--nav-key-bindings
  '(([up]      . kuro--arrow-up)
    ([down]    . kuro--arrow-down)
    ([left]    . kuro--arrow-left)
    ([right]   . kuro--arrow-right)
    ([home]    . kuro--HOME)
    ([end]     . kuro--END)
    ([prior]   . kuro--PAGE-UP)
    ([next]    . kuro--PAGE-DOWN)
    ([delete]  . kuro--DELETE)
    ([insert]  . kuro--INSERT)
    ([S-prior] . kuro-scroll-up)
    ([S-next]  . kuro-scroll-down)
    ([S-end]   . kuro-scroll-bottom))
  "Alist of (KEY-VECTOR . COMMAND) pairs for navigation keys.
Covers arrow keys, home/end/page/insert/delete, and scrollback viewport.
Applied by `kuro--keymap-setup-navigation'.")

(defun kuro--keymap-setup-navigation (map)
  "Add arrow, home, end, page, function key and modifier+arrow bindings to MAP."
  ;; Static navigation keys: arrows, home/end/page/insert/delete, scrollback
  (pcase-dolist (`(,key . ,cmd) kuro--nav-key-bindings)
    (define-key map key cmd))

  ;; Function keys F1–F12
  (dolist (entry kuro--fkey-handlers)
    (define-key map (vector (car entry)) (cdr entry)))

  ;; Modifier + arrow keys: xterm CSI 1;Nm sequences
  (dolist (mod kuro--xterm-modifier-codes)
    (dolist (arrow kuro--xterm-arrow-codes)
      (let* ((event (intern (format "%s-%s" (car mod) (car arrow))))
             (seq   (format "\e[1;%d%c" (cdr mod) (cdr arrow))))
        (define-key map (vector event)
          (lambda () (interactive)
            (kuro--send-key seq)
            (kuro--schedule-immediate-render)))))))

(defconst kuro--mouse-bindings
  '(([down-mouse-1] . kuro--mouse-press)
    ([down-mouse-2] . kuro--mouse-press)
    ([down-mouse-3] . kuro--mouse-press)
    ([mouse-1]      . kuro--mouse-release)
    ([mouse-2]      . kuro--mouse-release)
    ([mouse-3]      . kuro--mouse-release)
    ([mouse-4]      . kuro--mouse-scroll-up)
    ([mouse-5]      . kuro--mouse-scroll-down))
  "Alist of (KEY-VECTOR . COMMAND) pairs for mouse event bindings.
Applied by `kuro--keymap-setup-mouse'.")

(defun kuro--keymap-setup-mouse (map)
  "Add mouse event bindings to MAP using `kuro--mouse-bindings'."
  (pcase-dolist (`(,key . ,cmd) kuro--mouse-bindings)
    (define-key map key cmd)))

(defun kuro--keymap-setup-yank (map)
  "Add yank remapping and keymap-exception removal to MAP.
Remaps `yank' (C-y), `yank-pop' (M-y), and `clipboard-yank' (Cmd+V on macOS)
all to `kuro--yank' / `kuro--yank-pop' so paste always goes through the PTY
with optional bracketed-paste wrapping."
  (define-key map [remap yank]          #'kuro--yank)
  (define-key map [remap yank-pop]      #'kuro--yank-pop)
  (define-key map [remap clipboard-yank] #'kuro--yank)

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
      (error nil))))


;;; Keymap Builder

(defun kuro--build-keymap ()
  "Build and return the Kuro terminal input keymap.
Keys listed in `kuro-keymap-exceptions' are omitted so they fall through
to the standard Emacs global keymap.  Also stores the result in
`kuro--keymap' for use as the parent of `kuro-mode-map'."
  (let ((map (make-sparse-keymap)))
    (define-key map [remap self-insert-command] #'kuro--self-insert)
    (kuro--keymap-setup-special map)
    (kuro--keymap-setup-ctrl map)
    (kuro--keymap-setup-meta map)
    (kuro--keymap-setup-navigation map)
    (kuro--keymap-setup-mouse map)
    (kuro--keymap-setup-yank map)
    (setq kuro--keymap map)
    map))

(provide 'kuro-input-keymap)

;;; kuro-input-keymap.el ends here
