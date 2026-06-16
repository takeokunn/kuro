;;; kuro-input-keymap.el --- Terminal input keymap for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Builds `kuro--keymap', the parent keymap of `kuro-mode-map'.
;;
;; Key categories are split into per-function setup helpers:
;; `kuro--keymap-setup-special' (RET/TAB/DEL/ESC),
;; `kuro--keymap-setup-ctrl' (C-a..C-z control bytes),
;; `kuro--keymap-setup-meta' (M-a..M-z and Meta-punctuation via ESC prefix),
;; `kuro--keymap-setup-navigation' (arrows, home/end, page, F1-F12,
;; modifier+arrow xterm sequences), `kuro--keymap-setup-mouse' (X10/SGR
;; mouse events), and `kuro--keymap-setup-yank' (bracketed paste yank).
;;
;; Keys listed in `kuro-keymap-exceptions' are removed at build time so
;; they fall through to the global keymap (e.g. M-x, C-g).

;;; Code:

(require 'kuro-ffi)
(require 'kuro-input-mouse)
(require 'kuro-input-paste)
(require 'kuro-keymap)

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
(declare-function kuro--kkp-flag-p "kuro-input-keys" (flag))

;; kuro--keyboard-flags is defvar-permanent-local in kuro-input-paste.el.
;; Forward-declare here so the escape-key lambda can reference it.
(defvar kuro--keyboard-flags 0
  "Forward reference; defvar-permanent-local in kuro-input-paste.el.")

;; kuro--kkp-* constants are defconst in kuro-input-keys.el (loaded before this file
;; via kuro-input.el). Declare them here to silence byte-compiler warnings.
(defvar kuro--kkp-disambiguate  #x01 "Forward reference; defconst in kuro-input-keys.el.")
(defvar kuro--kkp-all-escape    #x08 "Forward reference; defconst in kuro-input-keys.el.")


;;; Keymap Variable

(defvar kuro--keymap nil
  "Keymap for Kuro terminal emulator.  Built by `kuro--build-keymap'.")


;;; Keymap Helper Functions

(defun kuro--keymap-setup-special (map)
  "Add special key bindings to MAP (RET, TAB, DEL, escape, Ctrl variants)."
  ;; [return] and (kbd "C-m") are both ?\r (ASCII 13) in terminal semantics.
  ;; [tab] and (kbd "C-i") are both ?\t.
  ;; [backspace] is DEL (127); (kbd "C-h") is BS (8) — both must work.
  (kuro--bind-keys map #'kuro--RET [return] (kbd "C-m"))
  (kuro--bind-keys map #'kuro--TAB [tab] (kbd "C-i"))
  (kuro--bind-keys map #'kuro--DEL [backspace] (kbd "C-h") (kbd "DEL"))
  ;; C-h must also send DEL (127) — in terminals, backspace sends 127 and C-h
  ;; also traditionally sends 127 (or 8 depending on stty).  Sending 127 is
  ;; the modern default that matches xterm/kitty.
  ;; DEL (127) — same as [backspace]; some terminals send this for C-?
  )

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
  \\(logand char 31\\): values range from 1 (Control-A) to 26 (Control-Z).
The kuro-mode prefix key is intentionally absent from this map.")

(defun kuro--bind-ctrl-key (map key byte)
  "Bind KEY in MAP to send CTRL-BYTE to the PTY."
  (define-key map (kbd key)
    (lambda () (interactive) (kuro--send-ctrl byte))))

(defun kuro--send-escape ()
  "Send Escape to the PTY, preserving KKP disambiguation when enabled."
  (interactive)
  (if (not (zerop (logand kuro--keyboard-flags #x01)))
      (progn (kuro--send-key "\e[27;1u") (kuro--schedule-immediate-render))
    (kuro--send-ctrl 27)))

(defun kuro--keymap-setup-ctrl (map)
  "Add Ctrl+letter bindings to MAP, forwarding each to the PTY as control byte.
Uses `kuro--ctrl-key-table' to map Emacs key strings to ASCII control codes."
  (dolist (entry kuro--ctrl-key-table)
    (kuro--bind-ctrl-key map (car entry) (cdr entry)))
  ;; C-v: scroll-aware — scrolls when in scrollback, sends ctrl byte when at live view.
  (define-key map (kbd "C-v") #'kuro--scroll-aware-ctrl-v)
  ;; ESC must use [escape] (not kbd "ESC") to avoid shadowing all ESC-prefixed bindings.
  ;; With KKP DISAMBIGUATE (0x01): send CSI 27;1u so the app sees an unambiguous Escape
  ;; event, rather than a bare \e that could be mistaken as the start of an escape sequence.
  (define-key map [escape] #'kuro--send-escape))

(defun kuro--send-meta-backspace ()
  "Send ESC+DEL (Meta-Backspace) to the PTY.
This is the standard control sequence for `backward-kill-word' in readline/bash."
  (interactive)
  (kuro--send-key (string ?\e ?\x7f))
  (kuro--schedule-immediate-render))

(defun kuro--bind-meta-key (map key char)
  "Bind KEY and its ESC-prefix fallback to a meta sender for CHAR."
  (let ((command (lambda () (interactive) (kuro--send-meta char))))
    (define-key map key command)
    (define-key map (vector ?\e char) command)))

(defun kuro--meta-exception-char (exc)
  "Return the single-character Meta suffix from EXC, or nil."
  (when (and (string-prefix-p "M-" exc)
             (= (length exc) 3))
    (aref exc 2)))

(defun kuro--keymap-clear-exception (map exc)
  "Unbind EXC in MAP and clear its ESC-prefix fallback when applicable."
  (ignore-errors
    (define-key map (kbd exc) nil)
    (let ((char (kuro--meta-exception-char exc)))
      (when char
        (define-key map (vector ?\e char) nil)))))

(defconst kuro--meta-punct-bindings
  '(("M-." . ?.) ("M-<" . ?<) ("M->" . ?>)
    ("M-?" . ??) ("M-/" . ?/) ("M-_" . ?_))
  "Alist of (KBD-STRING . CHAR) for Meta+punctuation bindings.
Each entry maps an Emacs key string to the character sent via `kuro--send-meta'.
Applied by `kuro--keymap-setup-meta'.
M-DEL and M-<backspace> are handled separately
\(they call `kuro--send-meta-backspace').")

(defun kuro--keymap-setup-meta (map)
  "Add Meta/Alt bindings for all letters and related keys to MAP.

In readline, Alt+key is sent as ESC then the key character.  These are
the bash readline Alt bindings most frequently used (each is forwarded as
ESC + the corresponding character byte to the PTY):
  Meta-b  — move word left          Meta-f  — move word right
  Meta-d  — delete word forward     Meta-DEL — delete word backward
  Meta-.  — insert last argument    Meta-r  — revert-line
  Meta-u  — uppercase word          Meta-l  — lowercase word
  Meta-c  — capitalize word         Meta-t  — transpose words
  Meta-y  — `yank-pop'              Meta-<  — beginning of history
  Meta->  — end of history          Meta-?  — possible completions
  Meta-/  — complete filename

The loop runs FIRST so that explicit overrides below take precedence.
Use (kbd (format \"M-%c\" char)) — this produces the correct event descriptor
in both terminal and GUI Emacs.  (vector (list \='meta char)) is NOT equivalent
and would be silently ignored in GUI frames."
  ;; Bind ALL M-a … M-z, M-A … M-Z, M-0 … M-9 via loop.
  ;; The helper also installs the ESC-prefix fallback used by terminal Meta keys.
  (dolist (char (append (number-sequence ?a ?z) (number-sequence ?A ?Z)
                        (number-sequence ?0 ?9)))
    (kuro--bind-meta-key map (kbd (format "M-%c" char)) char))

  ;; Keys outside the a-z/A-Z/0-9 ranges — not covered by the dolist above.
  (dolist (entry kuro--meta-punct-bindings)
    (kuro--bind-meta-key map (kbd (car entry)) (cdr entry)))
  ;; M-v: scroll-aware — scrolls when in scrollback, sends ESC+v when at live view.
  (kuro--bind-keys map #'kuro--scroll-aware-meta-v (kbd "M-v") (vector ?\e ?v))
  ;; M-DEL — delete word backward (sends ESC + DEL = ESC + 127)
  (kuro--bind-keys map #'kuro--send-meta-backspace
                   (kbd "M-DEL")
                   (kbd "M-<backspace>")))

(defconst kuro--xterm-modifier-codes
  '((S . 2) (M . 3) (C . 5))
  "Xterm CSI modifier parameter codes used in \\e[1;Nm sequences.
Shift=2, Alt/Meta=3, Ctrl=5.  Note: code 4 (Shift+Alt) is absent here
because Emacs does not generate a distinct [S-M-up] event.")

(defconst kuro--xterm-arrow-codes
  '((up . ?A) (down . ?B) (right . ?C) (left . ?D))
  "Xterm CSI final-byte characters for arrow directions in \\e[1;Nm sequences.
The letters A/B/C/D are the original VT100 cursor movement codes
\(CUU/CUD/CUF/CUB).  Used with `kuro--xterm-modifier-codes' to build the 12
modifier+arrow sequences like \\e[1;2A (Shift+Up), \\e[1;5C (Ctrl+Right), etc.")

(defconst kuro--kkp-arrow-codepoints
  '((up . 57352) (down . 57353) (right . 57351) (left . 57350))
  "KKP Unicode codepoints for arrow keys.
Used when `kuro--kkp-all-escape' (0x08) is active to send CSI cp;mod u instead
of the xterm CSI 1;Nm form.  Mirrors `kuro--xterm-arrow-codes' key order.")

(defconst kuro--fkey-handlers
  '((f1  . kuro--F1)  (f2  . kuro--F2)  (f3  . kuro--F3)  (f4  . kuro--F4)
    (f5  . kuro--F5)  (f6  . kuro--F6)  (f7  . kuro--F7)  (f8  . kuro--F8)
    (f9  . kuro--F9)  (f10 . kuro--F10) (f11 . kuro--F11) (f12 . kuro--F12))
  "Alist mapping Emacs function-key event symbols to Kuro handler commands.")

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

(defmacro kuro--def-shifted-key (name kkp-seq legacy-seq docstring)
  "Define NAME as an interactive key-sender dispatching on KKP state.
DOCSTRING becomes the generated command docstring.
Sends KKP-SEQ when the flag is active, or LEGACY-SEQ otherwise.
Then schedule a render."
  `(defun ,name ()
     ,docstring
     (interactive)
     (kuro--send-key (if (kuro--kkp-flag-p kuro--kkp-disambiguate)
                         ,kkp-seq
                       ,legacy-seq))
     (kuro--schedule-immediate-render)))

(defun kuro--send-modifier-arrow (xterm-seq kkp-cp kkp-mod)
  "Return a command that sends XTERM-SEQ or the matching KKP sequence."
  (lambda ()
    (interactive)
    (if (and kkp-cp (kuro--kkp-flag-p kuro--kkp-all-escape))
        (kuro--send-key (format "\e[%d;%du" kkp-cp kkp-mod))
      (kuro--send-key xterm-seq))
    (kuro--schedule-immediate-render)))

(defun kuro--bind-modifier-arrow (map mod-sym dir xterm-mod final-byte)
  "Bind a modifier+arrow event in MAP for MOD-SYM and DIR."
  (let* ((event    (intern (format "%s-%s" mod-sym dir)))
         (xterm-seq (format "\e[1;%d%c" xterm-mod final-byte))
         ;; KKP wire modifier: shift=1→2, alt=2→3, ctrl=4→5
         (kkp-mod  (1+ xterm-mod))
         (kkp-cp   (cdr (assq dir kuro--kkp-arrow-codepoints))))
    (define-key map (vector event)
      (kuro--send-modifier-arrow xterm-seq kkp-cp kkp-mod))))

(kuro--def-shifted-key kuro--send-shifted-tab
  "\e[9;2u" "\e[Z"
  "Send Shift+Tab to the PTY: KKP CSI 9;2u or legacy ESC [ Z.")

(kuro--def-shifted-key kuro--send-shifted-return
  "\e[13;2u" "\r"
  "Send Shift+Return to the PTY: KKP CSI 13;2u or legacy CR.")

(defun kuro--keymap-setup-navigation (map)
  "Add arrow, home, end, page, function key and modifier+arrow bindings to MAP."
  ;; Static navigation keys: arrows, home/end/page/insert/delete, scrollback
  (kuro--bind-key-alist map kuro--nav-key-bindings
                        (lambda (binding) (car binding))
                        #'cdr)

  ;; Function keys F1–F12
  (kuro--bind-key-alist map kuro--fkey-handlers
                        (lambda (binding) (vector (car binding)))
                        #'cdr)

  ;; Modifier + arrow keys: xterm CSI 1;Nm sequences (or KKP with flag 0x08)
  (dolist (mod kuro--xterm-modifier-codes)
    (dolist (arrow kuro--xterm-arrow-codes)
      (kuro--bind-modifier-arrow map (car mod) (car arrow) (cdr mod) (cdr arrow))))

  ;; Shift+Tab: [backtab] (X11) and [S-tab] (some terminals) are the same event.
  (kuro--bind-keys map #'kuro--send-shifted-tab [backtab] [S-tab])
  ;; Shift+Return: legacy = CR; KKP = CSI 13;2u
  (define-key map [S-return] #'kuro--send-shifted-return))

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
  (kuro--bind-key-alist map kuro--mouse-bindings
                        (lambda (binding) (car binding))
                        #'cdr))

(defconst kuro--yank-bindings
  '((yank          . kuro--yank)
    (yank-pop      . kuro--yank-pop)
    (clipboard-yank . kuro--yank))
  "Alist of (EMACS-CMD . KURO-CMD) remap entries for paste interception.
Each entry remaps an Emacs yank command to its kuro equivalent so all paste
paths go through the PTY with optional bracketed-paste wrapping.
Applied by `kuro--keymap-setup-yank'.")

(defun kuro--keymap-setup-yank (map)
  "Add yank remapping to MAP using `kuro--yank-bindings'.
Remaps `yank', `yank-pop', and `clipboard-yank' (Cmd+V on macOS)
all to `kuro--yank' / `kuro--yank-pop' so paste always goes through the PTY
with optional bracketed-paste wrapping."
  (kuro--bind-key-alist map kuro--yank-bindings
                        (lambda (binding) (vector 'remap (car binding)))
                        #'cdr))

(defun kuro--keymap-apply-exceptions (map)
  "Remove exception keys from MAP per `kuro-keymap-exceptions'.
Keys in `kuro-keymap-exceptions' fall through to the standard Emacs
global keymap.
Called on the semi-char keymap; NOT called when building the char keymap."
  (dolist (exc (bound-and-true-p kuro-keymap-exceptions))
    (kuro--keymap-clear-exception map exc)))


;;; Keymap Variables

(defvar kuro--char-keymap nil
  "Full Kuro keymap with ALL keys bound (char mode: no exceptions).
Built by `kuro--build-keymap' alongside `kuro--keymap'.")


;;; Keymap Builder

(defun kuro--build-full-keymap ()
  "Build and return a full Kuro keymap with all keys bound (no exceptions).
This is the char-mode base; used directly in char mode and as the basis
for `kuro--keymap' (semi-char) after exception removal."
  (let ((map (make-sparse-keymap)))
    (define-key map [remap self-insert-command] #'kuro--self-insert)
    (kuro--keymap-setup-special map)
    (kuro--keymap-setup-ctrl map)
    (kuro--keymap-setup-meta map)
    (kuro--keymap-setup-navigation map)
    (kuro--keymap-setup-mouse map)
    (kuro--keymap-setup-yank map)
    map))

(defun kuro--build-keymap ()
  "Build `kuro--keymap' (semi-char) and `kuro--char-keymap' (char mode).
`kuro--char-keymap': all keys bound, no exceptions — used in char mode.
`kuro--keymap': exceptions from `kuro-keymap-exceptions' removed — default.
Returns `kuro--keymap' for backward compatibility."
  (setq kuro--char-keymap (kuro--build-full-keymap))
  ;; Semi-char: start from a copy of the full keymap, then punch holes
  (let ((map (copy-keymap kuro--char-keymap)))
    (kuro--keymap-apply-exceptions map)
    (setq kuro--keymap map)
    map))

(provide 'kuro-input-keymap)

;;; kuro-input-keymap.el ends here
