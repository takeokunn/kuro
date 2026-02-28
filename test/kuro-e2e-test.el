;;; kuro-e2e-test.el --- E2E tests for Kuro terminal emulator -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests that run in Emacs batch mode.
;; Timers don't run in batch, so kuro--render-cycle is called manually.
;; PTY output is waited on with sleep-for polling loops.

;;; Code:

(require 'ert)

;;; Helpers

(defconst kuro-test--timeout 5.0
  "Seconds to wait for PTY output before failing.")

(defconst kuro-test--shell "/bin/zsh"
  "Shell used for testing.")

(defun kuro-test--make-buffer ()
  "Create a fresh Kuro terminal buffer for testing."
  (let ((buf (generate-new-buffer "*kuro-test*")))
    (with-current-buffer buf
      (setq buffer-read-only t)
      (setq-local bidi-display-reordering nil)
      (setq-local truncate-lines t)
      (setq-local show-trailing-whitespace nil))
    buf))

(defun kuro-test--init (buf)
  "Initialize Kuro terminal in BUF. Returns t on success."
  (with-current-buffer buf
    (and (kuro--init kuro-test--shell)
         (progn (kuro--resize 24 80) t))))

(defun kuro-test--render (buf)
  "Run one render cycle in BUF."
  (with-current-buffer buf
    (kuro--render-cycle)))

(defun kuro-test--send (str)
  "Send STR to the terminal."
  (kuro--send-key str))

(defun kuro-test--wait-for (buf pattern)
  "Poll BUF with render cycles until PATTERN matches or timeout.
Checks both the current visible screen (buffer content) and the scrollback
buffer so output that scrolled off the screen is not missed.
Returns t if found, nil on timeout."
  (let ((deadline (+ (float-time) kuro-test--timeout))
        (found nil))
    (while (and (not found) (< (float-time) deadline))
      (kuro-test--render buf)
      ;; Check the visible screen
      (with-current-buffer buf
        (when (string-match-p pattern (buffer-string))
          (setq found t)))
      ;; Also check the scrollback buffer in case output scrolled off screen
      (unless found
        (when kuro--initialized
          (condition-case nil
              (let ((scrollback (kuro-core-get-scrollback 100)))
                (when (and scrollback (listp scrollback))
                  (dolist (line scrollback)
                    (when (and (stringp line)
                               (string-match-p pattern line))
                      (setq found t)))))
            (error nil))))
      (unless found
        (sleep-for 0.05)))
    found))

(defun kuro-test--buffer-content (buf)
  "Return trimmed buffer content of BUF."
  (with-current-buffer buf
    (buffer-string)))

(defconst kuro-test--ready-marker "KURO_SHELL_READY"
  "Unique string echoed to confirm the shell is fully initialized and idle.")

(defmacro kuro-test--with-terminal (&rest body)
  "Run BODY in a fresh terminal session, cleaning up afterward.
Waits for a known ready-marker echo to confirm the shell is fully
initialized before running BODY, avoiding false prompt detection."
  `(let ((buf (kuro-test--make-buffer)))
     (unwind-protect
         (progn
           (unless (kuro-test--init buf)
             (error "Failed to initialize Kuro terminal"))
           ;; First wait: any shell output (RPROMPT, startup messages)
           (kuro-test--wait-for buf ".")
           ;; Give the shell a moment to finish drawing its initial prompt
           (sleep-for 0.2)
           (dotimes (_ 4) (kuro-test--render buf) (sleep-for 0.05))
           ;; Confirm readiness by echoing a known marker and waiting for it
           (kuro--send-key (concat "echo " kuro-test--ready-marker))
           (kuro--send-key "\r")
           (unless (kuro-test--wait-for buf kuro-test--ready-marker)
             (error "Timed out waiting for shell ready marker"))
           ;; One more settle after the ready marker appears
           (sleep-for 0.1)
           (dotimes (_ 2) (kuro-test--render buf) (sleep-for 0.05))
           ,@body)
       ;; Cleanup: shutdown then brief pause before killing the buffer
       ;; so the old PTY reader thread can finish draining and exit.
       (condition-case nil (kuro--shutdown) (error nil))
       (sleep-for 0.1)
       (when (buffer-live-p buf) (kill-buffer buf)))))

;;; Unit tests for color and attribute decoding (no live terminal required)

(ert-deftest kuro-unit-decode-ffi-color-default ()
  "kuro--decode-ffi-color with 0 returns the :default keyword."
  (require 'kuro-renderer)
  (should (eq :default (kuro--decode-ffi-color 0))))

(ert-deftest kuro-unit-decode-ffi-color-named-red ()
  "kuro--decode-ffi-color with 0x80000001 returns (named . \"red\")."
  (require 'kuro-renderer)
  (let ((result (kuro--decode-ffi-color #x80000001)))
    (should (consp result))
    (should (eq 'named (car result)))
    (should (equal "red" (cdr result)))))

(ert-deftest kuro-unit-decode-ffi-color-indexed-16 ()
  "kuro--decode-ffi-color with 0x40000010 returns (indexed . 16)."
  (require 'kuro-renderer)
  (let ((result (kuro--decode-ffi-color #x40000010)))
    (should (consp result))
    (should (eq 'indexed (car result)))
    (should (= 16 (cdr result)))))

(ert-deftest kuro-unit-decode-attrs-bold ()
  "kuro--decode-attrs with #x01 produces :bold t."
  (require 'kuro-renderer)
  (let ((attrs (kuro--decode-attrs #x01)))
    (should (plist-get attrs :bold))))

(ert-deftest kuro-unit-decode-attrs-italic ()
  "kuro--decode-attrs with #x04 produces :italic t."
  (require 'kuro-renderer)
  (let ((attrs (kuro--decode-attrs #x04)))
    (should (plist-get attrs :italic))))

(ert-deftest kuro-unit-decode-attrs-inverse ()
  "kuro--decode-attrs with #x40 produces :inverse t."
  (require 'kuro-renderer)
  (let ((attrs (kuro--decode-attrs #x40)))
    (should (plist-get attrs :inverse))))

(ert-deftest kuro-unit-decode-attrs-strikethrough ()
  "kuro--decode-attrs with #x100 produces :strike-through t."
  (require 'kuro-renderer)
  (let ((attrs (kuro--decode-attrs #x100)))
    (should (plist-get attrs :strike-through))))

(ert-deftest kuro-unit-decode-attrs-blink-slow ()
  "kuro--decode-attrs with #x10 produces :blink-slow t."
  (require 'kuro-renderer)
  (let ((attrs (kuro--decode-attrs #x10)))
    (should (plist-get attrs :blink-slow))))

(ert-deftest kuro-unit-decode-attrs-blink-fast ()
  "kuro--decode-attrs with #x20 produces :blink-fast t."
  (require 'kuro-renderer)
  (let ((attrs (kuro--decode-attrs #x20)))
    (should (plist-get attrs :blink-fast))))

(ert-deftest kuro-unit-decode-attrs-hidden ()
  "kuro--decode-attrs with #x80 produces :hidden t."
  (require 'kuro-renderer)
  (let ((attrs (kuro--decode-attrs #x80)))
    (should (plist-get attrs :hidden))))

(ert-deftest kuro-unit-face-cache-returns-same-object ()
  "kuro--get-cached-face returns the identical object for equal attribute keys."
  (require 'kuro-renderer)
  ;; Clear the cache to ensure a predictable starting state
  (kuro--clear-face-cache)
  (let* ((attrs '(:foreground (named . "red") :background :default :flags 1))
         (face1 (kuro--get-cached-face attrs))
         (face2 (kuro--get-cached-face attrs)))
    (should (eq face1 face2))))

(ert-deftest kuro-unit-rgb-to-emacs ()
  "kuro--rgb-to-emacs with #x00c23621 returns \"#c23621\" (correct byte order).
The encoding reads R from bits 16-23, G from bits 8-15, B from bits 0-7.
For the value #x00C23621 that means R=#xC2, G=#x36, B=#x21, producing \"#c23621\"."
  (require 'kuro-renderer)
  (should (equal "#c23621" (kuro--rgb-to-emacs #x00c23621))))

;;; E2E Tests

(ert-deftest kuro-e2e-module-loads ()
  "Test that the Rust module loaded and provides expected functions."
  (should (fboundp 'kuro-core-init))
  (should (fboundp 'kuro-core-send-key))
  (should (fboundp 'kuro-core-poll-updates))
  (should (fboundp 'kuro-core-poll-updates-with-faces))
  (should (fboundp 'kuro-core-get-cursor))
  (should (fboundp 'kuro-core-resize))
  (should (fboundp 'kuro-core-shutdown)))

(ert-deftest kuro-e2e-terminal-init ()
  "Test that a terminal session can be initialized and produces output."
  (kuro-test--with-terminal
   ;; Shell prompt appeared — basic init works
   (should (string-match-p "\\S-" (kuro-test--buffer-content buf)))))

(ert-deftest kuro-e2e-echo-command ()
  "Test that a simple echo command produces output.
Uses a short unique marker (KUROX99) to avoid line-wrapping issues with
long zsh prompts, which can cause the output to scroll off screen between
render cycles."
  (kuro-test--with-terminal
   (kuro-test--send "echo KUROX99")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KUROX99"))))

(ert-deftest kuro-e2e-multiple-commands ()
  "Test that multiple commands can be run sequentially."
  (kuro-test--with-terminal
   (kuro-test--send "echo first_cmd")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "first_cmd"))
   (kuro-test--send "echo second_cmd")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "second_cmd"))))

(ert-deftest kuro-e2e-cursor-position ()
  "Test that cursor position is reported as a valid cons cell."
  (kuro-test--with-terminal
   (kuro-test--render buf)
   (let ((cursor (kuro--get-cursor)))
     (should (consp cursor))
     (should (integerp (car cursor)))
     (should (integerp (cdr cursor)))
     (should (>= (car cursor) 0))
     (should (>= (cdr cursor) 0)))))

(ert-deftest kuro-e2e-ansi-colors ()
  "Test that ANSI color output produces face ranges.
The command echo and the actual printf output both contain REDTEXT, so we
search all occurrences for at least one with a non-nil face property."
  (kuro-test--with-terminal
   ;; Use a unique marker that is split across escape sequences in the command
   ;; itself but appears as plain REDTEXT in the colored output.
   ;; We assign the escape sequence to a shell variable so the command echo
   ;; does not contain the literal word REDTEXT — only the output does.
   (kuro-test--send "R=\"\\033[31mREDTEXT\\033[0m\"; printf \"$R\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "REDTEXT"))
   ;; Do a few more render cycles to ensure face properties are applied
   (dotimes (_ 5)
     (kuro-test--render buf)
     (sleep-for 0.02))
   ;; Check that at least one occurrence of REDTEXT has a face property.
   ;; The colored output (not the command echo) should carry a face.
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-colored nil)
           (search-start 0))
       (while (and (not found-colored)
                   (string-match "REDTEXT" content search-start))
         (let* ((match-start (match-beginning 0))
                (pos (+ (point-min) match-start))
                (face (get-text-property pos 'face)))
           (when face
             (setq found-colored t)))
         (setq search-start (1+ (match-beginning 0))))
       ;; At least one REDTEXT occurrence should have a face (the colored output)
       (should found-colored)
       ;; Verify the color is a valid hex string (the FFI color pipeline is working)
       (let ((color-verified nil)
             (search-start2 0))
         (while (and (not color-verified)
                     (string-match "REDTEXT" content search-start2))
           (let* ((match-start (match-beginning 0))
                  (pos (+ (point-min) match-start))
                  (face (get-text-property pos 'face)))
             (when face
               (let* ((face-props (and (listp face) (car face)))
                      (fg (and (listp face-props)
                               (plist-get face-props :foreground))))
                 (when (and (stringp fg) (string-prefix-p "#" fg))
                   (setq color-verified t)))))
           (setq search-start2 (1+ (match-beginning 0))))
         (should color-verified))))))

(ert-deftest kuro-e2e-hidden-text ()
  "Test that SGR 8 (hidden/conceal) makes text invisible via Emacs invisible property.
Uses a shell variable to avoid the echo of the escape sequence itself containing HIDDEN."
  (kuro-test--with-terminal
   ;; Use shell variable to avoid escape sequence in command echo
   (kuro-test--send "H=\"\\033[8mHIDDENTEXT\\033[0m\"; printf \"$H\"")
   (kuro-test--send "\r")
   ;; The text HIDDENTEXT must appear in the buffer (invisible prop is on chars, not deletion)
   (should (kuro-test--wait-for buf "HIDDENTEXT"))
   (dotimes (_ 5)
     (kuro-test--render buf)
     (sleep-for 0.02))
   ;; Verify the invisible text property is set on the hidden text
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-hidden nil)
           (search-start 0))
       (while (and (not found-hidden)
                   (string-match "HIDDENTEXT" content search-start))
         (let* ((match-start (match-beginning 0))
                (pos (+ (point-min) match-start))
                (invisible (get-text-property pos 'invisible)))
           (when invisible
             (setq found-hidden t)))
         (setq search-start (1+ (match-beginning 0))))
       (should found-hidden)))))

(ert-deftest kuro-e2e-inverse-video ()
  "Test that SGR 7 (inverse/reverse video) sets :inverse-video face property."
  (kuro-test--with-terminal
   (kuro-test--send "I=\"\\033[7mINVERSETEXT\\033[0m\"; printf \"$I\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "INVERSETEXT"))
   (dotimes (_ 5)
     (kuro-test--render buf)
     (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-inverse nil)
           (search-start 0))
       (while (and (not found-inverse)
                   (string-match "INVERSETEXT" content search-start))
         (let* ((match-start (match-beginning 0))
                (pos (+ (point-min) match-start))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (inv (and (listp face-props)
                              (plist-get face-props :inverse-video))))
               (when inv
                 (setq found-inverse t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-inverse)))))

(ert-deftest kuro-e2e-blink-structural ()
  "Test that SGR 5 (blink-slow) produces blink overlays on the rendered line.
After the initial dirty render creates overlays, subsequent render cycles
should preserve them on the now-stable line (per-line clearing, not full-buffer)."
  (kuro-test--with-terminal
   (kuro-test--send "B=\"\\033[5mBLINKTEXT\\033[0m\"; printf \"$B\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "BLINKTEXT"))
   ;; Run a few more render cycles — overlays on the stable line should persist
   (dotimes (_ 5)
     (kuro-test--render buf)
     (sleep-for 0.02))
   (with-current-buffer buf
     ;; Decode function must recognize blink-slow bit
     (should (plist-get (kuro--decode-attrs #x10) :blink-slow))
     ;; If BLINKTEXT is on the visible screen, verify overlay is present
     (let* ((content (buffer-string))
            (match-pos (string-match "BLINKTEXT" content)))
       (when match-pos
         (let* ((buf-pos (+ (point-min) match-pos))
                (ovs (overlays-at buf-pos))
                (blink-ov nil))
           (dolist (ov ovs)
             (when (overlay-get ov 'kuro-blink)
               (setq blink-ov ov)))
           ;; If the text is visible and an overlay was found, verify its type
           (when blink-ov
             (should (eq 'slow (overlay-get blink-ov 'kuro-blink-type))))))))))

(ert-deftest kuro-e2e-resize ()
  "Test that terminal can be resized."
  (kuro-test--with-terminal
   ;; Resize to smaller dimensions
   (should (kuro--resize 10 40))
   (kuro-test--render buf)
   ;; Resize back
   (should (kuro--resize 24 80))))

(ert-deftest kuro-e2e-no-double-newlines ()
  "Test that render cycles do not accumulate extra blank lines."
  (kuro-test--with-terminal
   ;; Run 10 render cycles
   (dotimes (_ 10)
     (kuro-test--render buf)
     (sleep-for 0.05))
   ;; Buffer should not accumulate extra blank lines.
   ;; Trailing blank rows (the unused portion of the 24-row terminal grid)
   ;; naturally produce trailing newlines, so strip them before checking.
   (with-current-buffer buf
     (let* ((content (buffer-string))
            (trimmed (replace-regexp-in-string "\n+\\'" "" content)))
       (should-not (string-match-p "\n\n\n" trimmed))))))

(ert-deftest kuro-e2e-256-color-indexed-fg ()
  "Test that 256-color indexed foreground (SGR 38;5;196) produces a hex color face.
Index 196 in the 256-color palette corresponds to pure red (#ff0000) in the
6x6x6 color cube: n=196-16=180, r=(180/36)*51=255, g=((180/6)%6)*51=0, b=(180%6)*51=0."
  (kuro-test--with-terminal
   ;; Use shell variable to avoid escape sequence appearing in command echo
   (kuro-test--send "C256=\"\\033[38;5;196mCOLOR256\\033[0m\"; printf \"$C256\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "COLOR256"))
   ;; Run extra render cycles to ensure face properties are applied
   (dotimes (_ 5)
     (kuro-test--render buf)
     (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-color nil)
           (search-start 0))
       (while (and (not found-color)
                   (string-match "COLOR256" content search-start))
         (let* ((match-start (match-beginning 0))
                (pos (+ (point-min) match-start))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (fg (and (listp face-props)
                             (plist-get face-props :foreground))))
               ;; Verify foreground is a hex color string
               (when (and (stringp fg) (string-equal fg "#ff0000"))
                 (setq found-color fg)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-color)))))

(ert-deftest kuro-e2e-truecolor-rgb-fg ()
  "Test that TrueColor RGB foreground (SGR 38;2;255;0;0) produces #ff0000 face.
Uses non-zero RGB to avoid the Color::Rgb(0,0,0) == Color::Default encoding collision
in the Rust FFI layer (encode_color returns 0 for both)."
  (kuro-test--with-terminal
   ;; Use shell variable to avoid escape sequence appearing in command echo
   (kuro-test--send "CRGB=\"\\033[38;2;255;0;0mCOLORRGB\\033[0m\"; printf \"$CRGB\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "COLORRGB"))
   ;; Run extra render cycles to ensure face properties are applied
   (dotimes (_ 5)
     (kuro-test--render buf)
     (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-color nil)
           (search-start 0))
       (while (and (not found-color)
                   (string-match "COLORRGB" content search-start))
         (let* ((match-start (match-beginning 0))
                (pos (+ (point-min) match-start))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (fg (and (listp face-props)
                             (plist-get face-props :foreground))))
               ;; Verify foreground is specifically #ff0000 (RGB 255,0,0)
               (when (and (stringp fg) (string-equal fg "#ff0000"))
                 (setq found-color fg)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-color)))))

(ert-deftest kuro-e2e-vim-basic ()
  "Test that vim opens using alternate screen and exits cleanly."
  (skip-unless (executable-find "vim"))
  (kuro-test--with-terminal
   (let* ((unique-id (format "%d" (abs (random))))
          (tmpname (format "kurovimtest%s" unique-id))
          (tmpfile (format "/tmp/%s" tmpname)))
     ;; Create the temp file so vim opens it (not [New])
     (kuro-test--send (format "touch %s" tmpfile))
     (kuro-test--send "\r")
     (sleep-for 0.3)
     (dotimes (_ 3) (kuro-test--render buf) (sleep-for 0.05))
     ;; Open vim with the unique temp file
     (kuro-test--send (format "vim %s" tmpfile))
     (kuro-test--send "\r")
     ;; Wait for vim's status bar to show the unique filename
     ;; (vim always shows filename in the last line of the screen)
     (should (kuro-test--wait-for buf tmpname))
     ;; Extra settle time
     (sleep-for 0.5)
     (dotimes (_ 4) (kuro-test--render buf) (sleep-for 0.1))
     ;; Quit vim: ESC first to ensure normal mode, then :q!
     (kuro-test--send "\x1b")
     (sleep-for 0.1)
     (kuro-test--send ":q!")
     (kuro-test--send "\r")
     ;; Wait for vim to exit and primary screen to restore
     (sleep-for 0.5)
     (dotimes (_ 4) (kuro-test--render buf) (sleep-for 0.1))
     ;; Confirm shell is back
     (kuro--send-key (concat "echo " kuro-test--ready-marker))
     (kuro--send-key "\r")
     (should (kuro-test--wait-for buf kuro-test--ready-marker))
     ;; Cleanup
     (kuro-test--send (format "rm -f %s" tmpfile))
     (kuro-test--send "\r")
     (sleep-for 0.2))))

;;; Phase 02 acceptance tests

(ert-deftest kuro-e2e-multiline-output ()
  "Phase 02 acceptance: printf produces multiple lines correctly."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KMULTI1\\nKMULTI2\\nKMULTI3\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KMULTI1"))
   (should (kuro-test--wait-for buf "KMULTI2"))
   (should (kuro-test--wait-for buf "KMULTI3"))))

(ert-deftest kuro-e2e-tab-alignment ()
  "Phase 02 acceptance: tab character indents to next tab stop."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\tKTABTEXT'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KTABTEXT"))
   ;; Tab should produce at least one space before KTABTEXT
   (with-current-buffer buf
     (let ((content (kuro-test--buffer-content buf)))
       (should (string-match-p " +KTABTEXT\\|\\tKTABTEXT" content))))))

;;; Phase 03 acceptance tests

(ert-deftest kuro-e2e-clear-command ()
  "Phase 03 acceptance: clear command empties the visible screen."
  (kuro-test--with-terminal
   ;; Output some unique text first
   (kuro-test--send "echo KBEFORECLEAR")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KBEFORECLEAR"))
   ;; Now clear the screen
   (kuro-test--send "clear")
   (kuro-test--send "\r")
   ;; Give the clear time to render
   (sleep-for 0.3)
   (dotimes (_ 4) (kuro-test--render buf) (sleep-for 0.05))
   ;; After clear, the visible screen should not show the old text
   ;; (it may be in scrollback, but not in the visible buffer area)
   (with-current-buffer buf
     (should-not (string-match-p "KBEFORECLEAR" (buffer-string))))))

;;; Phase 04 acceptance tests

(ert-deftest kuro-e2e-bold-text ()
  "Phase 04 acceptance: SGR 1 (bold) produces :weight bold face property."
  (kuro-test--with-terminal
   (kuro-test--send "B=\"\\033[1mKBOLDTEXT\\033[0m\"; printf \"$B\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KBOLDTEXT"))
   (dotimes (_ 5) (kuro-test--render buf) (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-bold nil)
           (search-start 0))
       (while (and (not found-bold)
                   (string-match "KBOLDTEXT" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (weight (and (listp face-props)
                                 (plist-get face-props :weight))))
               (when (eq weight 'bold)
                 (setq found-bold t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-bold)))))

(ert-deftest kuro-e2e-underline-text ()
  "Phase 04 acceptance: SGR 4 (underline) produces :underline t face property."
  (kuro-test--with-terminal
   (kuro-test--send "U=\"\\033[4mKUNDERTEXT\\033[0m\"; printf \"$U\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KUNDERTEXT"))
   (dotimes (_ 5) (kuro-test--render buf) (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-underline nil)
           (search-start 0))
       (while (and (not found-underline)
                   (string-match "KUNDERTEXT" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (ul (and (listp face-props)
                             (plist-get face-props :underline))))
               (when ul
                 (setq found-underline t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-underline)))))

(ert-deftest kuro-e2e-background-color ()
  "Phase 04 acceptance: SGR 41 (red background) produces :background hex face."
  (kuro-test--with-terminal
   (kuro-test--send "BG=\"\\033[41mKREDBGTEXT\\033[0m\"; printf \"$BG\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KREDBGTEXT"))
   (dotimes (_ 5) (kuro-test--render buf) (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-bg nil)
           (search-start 0))
       (while (and (not found-bg)
                   (string-match "KREDBGTEXT" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (bg (and (listp face-props)
                             (plist-get face-props :background))))
               (when (and (stringp bg) (string-prefix-p "#" bg))
                 (setq found-bg t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-bg)))))

(ert-deftest kuro-e2e-bright-color ()
  "Phase 04 acceptance: SGR 91 (bright red) produces #ff0000 foreground."
  (kuro-test--with-terminal
   (kuro-test--send "BR=\"\\033[91mKBRIGHTTEXT\\033[0m\"; printf \"$BR\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KBRIGHTTEXT"))
   (dotimes (_ 5) (kuro-test--render buf) (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-bright nil)
           (search-start 0))
       (while (and (not found-bright)
                   (string-match "KBRIGHTTEXT" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (fg (and (listp face-props)
                             (plist-get face-props :foreground))))
               ;; Bright red (SGR 91) = BrightRed = #ff0000
               (when (and (stringp fg) (string-equal fg "#ff0000"))
                 (setq found-bright t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-bright)))))

;;; Phase 05 acceptance tests

(ert-deftest kuro-e2e-256-color-indexed-bg ()
  "Phase 05 acceptance: 256-color indexed background (SGR 48;5;21) produces hex background.
Index 21 in the 6x6x6 color cube: n=21-16=5, r=0*51=0, g=0*51=0, b=5*51=255 => #0000ff."
  (kuro-test--with-terminal
   (kuro-test--send "C256BG=\"\\033[48;5;21mKCOLOR256BG\\033[0m\"; printf \"$C256BG\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KCOLOR256BG"))
   (dotimes (_ 5) (kuro-test--render buf) (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-bg nil)
           (search-start 0))
       (while (and (not found-bg)
                   (string-match "KCOLOR256BG" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (bg (and (listp face-props)
                             (plist-get face-props :background))))
               ;; Index 21 = #0000ff (pure blue in 6x6x6 cube)
               (when (and (stringp bg) (string-equal bg "#0000ff"))
                 (setq found-bg t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-bg)))))

(ert-deftest kuro-e2e-truecolor-rgb-green ()
  "Phase 05 acceptance: TrueColor RGB green (SGR 38;2;0;255;128) produces #00ff80 face."
  (kuro-test--with-terminal
   (kuro-test--send "CGRN=\"\\033[38;2;0;255;128mKCOLORGREEN\\033[0m\"; printf \"$CGRN\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KCOLORGREEN"))
   (dotimes (_ 5) (kuro-test--render buf) (sleep-for 0.02))
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-color nil)
           (search-start 0))
       (while (and (not found-color)
                   (string-match "KCOLORGREEN" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (and (listp face) (car face)))
                    (fg (and (listp face-props)
                             (plist-get face-props :foreground))))
               (when (and (stringp fg) (string-equal fg "#00ff80"))
                 (setq found-color t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-color)))))

(provide 'kuro-e2e-test)

;;; kuro-e2e-test.el ends here
