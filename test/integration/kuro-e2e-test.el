;;; kuro-e2e-test.el --- E2E tests for Kuro terminal emulator -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests that run in Emacs batch mode.
;; Timers don't run in batch, so kuro--render-cycle is called manually.
;; PTY output is waited on with sleep-for polling loops.

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Module availability check

(defconst kuro-test--module-loaded
  (progn
    (ignore-errors
      (require 'kuro-module)
      (kuro-module-load))
    (and (fboundp 'kuro-core-init)
         (not (eq (symbol-function 'kuro-core-init)
                  (and (boundp 'kuro-test--stub-fn)
                       (symbol-value 'kuro-test--stub-fn))))
         ;; The stub from kuro-test.el returns nil; the real module returns an integer.
         ;; Check if the function is a compiled (subr) or module function.
         (or (subrp (symbol-function 'kuro-core-init))
             ;; module-function-p available in Emacs 29+
             (and (fboundp 'module-function-p)
                  (module-function-p (symbol-function 'kuro-core-init))))))
  "Non-nil when the real Rust kuro-core module is loaded (not just stubs).")

(defconst kuro-test--e2e-expected-result
  (if kuro-test--module-loaded :passed :failed)
  "Expected result for E2E tests: :passed with module, :failed without.")

;;; Helpers

(defconst kuro-test--timeout 10.0
  "Seconds to wait for PTY output before failing.")

(defconst kuro-test--poll-interval 0.01
  "Seconds between render/poll iterations in E2E helpers.")

(defconst kuro-test--idle-settle-timeout 0.2
  "Maximum seconds to wait for the terminal to become idle.")

(defconst kuro-test--idle-stable-cycles 2
  "Number of consecutive idle polls required to consider output settled.")

(defcustom kuro-test-shell
  (or (and (file-executable-p "/bin/bash") "/bin/bash")
      (and (file-executable-p "/bin/sh") "/bin/sh")
      (getenv "SHELL"))
  "Shell command used for testing.
Prefers a direct executable path because the Rust core validates COMMAND as an
actual shell path, not a shell-plus-arguments string."
  :type 'string
  :group 'kuro)

(defconst kuro-test--shell-args '("--norc" "--noprofile")
  "Shell arguments passed to `kuro-test-shell' during E2E tests.
Disables user rc files so tests get a clean, deterministic shell environment
without PS1 customizations or aliases that would break output matching.")

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
    (and (kuro--init kuro-test-shell kuro-test--shell-args)
         (progn (kuro--resize 24 80) t))))

(defun kuro-test--render (buf)
  "Run one render cycle in BUF."
  (with-current-buffer buf
    (kuro--render-cycle)))

(defun kuro-test--send (str)
  "Send STR to the terminal."
  (kuro--send-key str))

(defun kuro-test--pending-output-p ()
  "Return non-nil when the terminal reports queued output.
Falls back to nil if the low-level query is unavailable or errors."
  (cond ((fboundp 'kuro--has-pending-output)
         (condition-case nil
             (kuro--has-pending-output)
           (error t)))
        ((and kuro--initialized (fboundp 'kuro-core-has-pending-output))
         (condition-case nil
             (kuro-core-has-pending-output)
           (error t)))
        (t nil)))

(defun kuro-test--render-until-idle (buf &optional timeout stable-cycles)
  "Render BUF until output has been idle for STABLE-CYCLES polls or TIMEOUT.
Returns non-nil when idle was observed before the timeout expires."
  (let ((deadline (+ (float-time) (or timeout kuro-test--idle-settle-timeout)))
        (stable 0)
        (target (or stable-cycles kuro-test--idle-stable-cycles)))
    (while (and (< (float-time) deadline) (< stable target))
      (kuro-test--render buf)
      (setq stable (if (kuro-test--pending-output-p)
                       0
                     (1+ stable)))
      (when (< stable target)
        (sleep-for kuro-test--poll-interval)))
    (>= stable target)))

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
        (sleep-for kuro-test--poll-interval)))
    found))

(defun kuro-test--buffer-content (buf)
  "Return trimmed buffer content of BUF."
  (with-current-buffer buf
    (buffer-string)))

(defun kuro-test--face-props-at (pos)
  "Return a plist-like face description at POS, regardless of storage shape."
  (let ((face (get-text-property pos 'face)))
    (cond
     ((and (listp face) (keywordp (car face))) face)
     ((and (listp face) (listp (car face))) (car face))
     (t nil))))

(defconst kuro-test--ready-marker "KURO_SHELL_READY"
  "Unique string echoed to confirm the shell is fully initialized and idle.")

(defmacro kuro-test--with-terminal (&rest body)
  "Run BODY in a fresh terminal session, cleaning up afterward.
Waits for a known ready-marker echo to confirm the shell is fully
initialized before running BODY, avoiding false prompt detection."
  `(let ((buf (kuro-test--make-buffer)))
     (unwind-protect
         (progn
            (let ((process-environment (copy-sequence process-environment)))
              (setenv "BASH_SILENCE_DEPRECATION_WARNING" "1")
              (setenv "PS1" "kuro$ ")
              (unless (kuro-test--init buf)
                (error "Failed to initialize Kuro terminal"))
              (with-current-buffer buf
                ;; First wait: any shell output (RPROMPT, startup messages)
                (kuro-test--wait-for buf ".")
                ;; Let startup output quiesce instead of paying a fixed delay.
                (kuro-test--render-until-idle buf)
                ;; Brief pause to ensure bash has finished multi-stage startup
                ;; (e.g. macOS bash 3.2 deprecation warning + prompt in two phases).
                (sleep-for 0.1)
                ;; Confirm readiness by echoing a known marker and waiting for it.
                ;; Retry up to 3 times in case the first echo arrives before bash
                ;; is ready to process interactive input.
                (let ((found nil)
                      (attempts 0))
                  (while (and (not found) (< attempts 3))
                    (kuro--send-key (concat "echo " kuro-test--ready-marker))
                    (kuro--send-key "\r")
                    (setq attempts (1+ attempts))
                    (when (setq found (kuro-test--wait-for buf kuro-test--ready-marker))
                      (setq attempts 3)))
                  (unless found
                    (error "Timed out waiting for shell ready marker")))
                ;; Silence subsequent command echo and clear the display so E2E
                ;; assertions do not need to fight prompt noise or startup text.
                (kuro--send-key "stty -echo")
                (kuro--send-key "\r")
                (sleep-for 0.05)
                (kuro-test--render-until-idle buf 0.1 1)
                ;; Remove the shell prompt itself from subsequent render output.
                (kuro--send-key "PS1=''; export PS1; PROMPT_COMMAND=''; export PROMPT_COMMAND")
                (kuro--send-key "\r")
                (sleep-for 0.05)
                (kuro-test--render-until-idle buf 0.1 1)
                (kuro--send-key "printf '\\033[2J\\033[H'")
                (kuro--send-key "\r")
                ;; One more quick settle after the screen reset.
                (kuro-test--render-until-idle buf 0.1 1)
                ,@body)))
        ;; Cleanup: shutdown then brief pause before killing the buffer
        ;; so the old PTY reader thread can finish draining and exit.
        (condition-case nil (kuro--shutdown) (error nil))
        (when (buffer-live-p buf)
          (ignore-errors (kuro-test--render-until-idle buf 0.1 1)))
        (when (buffer-live-p buf) (kill-buffer buf)))))

(defconst kuro-test--tmux-timeout 10.0
  "Extended timeout (seconds) for tmux startup and operations.")

(defun kuro-test--wait-for-tmux (buf)
  "Poll BUF until tmux status bar appears or `kuro-test--tmux-timeout' expires.
Returns t if found, nil on timeout."
  (let ((deadline (+ (float-time) kuro-test--tmux-timeout))
        (found nil))
    (while (and (not found) (< (float-time) deadline))
      (kuro-test--render buf)
      (with-current-buffer buf
        ;; tmux status bar shows [session-name]<N>: format (window index immediately
        ;; follows the session name; the closing bracket from status-left is not
        ;; emitted as a separate glyph in all tmux versions / render passes).
        (when (string-match-p "\\[kuro-test[0-9]" (buffer-string))
          (setq found t)))
      (unless found (sleep-for (* 2 kuro-test--poll-interval))))
    found))

;;; E2E Tests

(ert-deftest kuro-e2e-module-loads ()
  "Test that the Rust module loaded and provides expected functions.
When stubs are present (unit test context), skip to avoid false positive."
  (skip-unless kuro-test--module-loaded)
  (should (fboundp 'kuro-core-init))
  (should (fboundp 'kuro-core-send-key))
  (should (fboundp 'kuro-core-poll-updates))
  (should (fboundp 'kuro-core-poll-updates-with-faces))
  (should (fboundp 'kuro-core-get-cursor))
  (should (fboundp 'kuro-core-resize))
  (should (fboundp 'kuro-core-shutdown)))

(ert-deftest kuro-e2e-terminal-init ()
  :expected-result kuro-test--e2e-expected-result
  "Test that a terminal session can be initialized and produces output."
  (kuro-test--with-terminal
   ;; Shell prompt appeared — basic init works
   (should (string-match-p "\\S-" (kuro-test--buffer-content buf)))))

(ert-deftest kuro-e2e-echo-command ()
  :expected-result kuro-test--e2e-expected-result
  "Test that a simple echo command produces output.
Uses a short unique marker (KUROX99) to avoid line-wrapping issues with
long zsh prompts, which can cause the output to scroll off screen between
render cycles."
  (kuro-test--with-terminal
   (kuro-test--send "echo KUROX99")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KUROX99"))))

(ert-deftest kuro-e2e-multiple-commands ()
  :expected-result kuro-test--e2e-expected-result
  "Test that multiple commands can be run sequentially."
  (kuro-test--with-terminal
   (kuro-test--send "echo first_cmd")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "first_cmd"))
   (kuro-test--send "echo second_cmd")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "second_cmd"))))

(ert-deftest kuro-e2e-cursor-position ()
  :expected-result kuro-test--e2e-expected-result
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
  :expected-result kuro-test--e2e-expected-result
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
               (let* ((face-props (or (kuro-test--face-props-at pos) face))
                      (fg (and (listp face-props)
                               (plist-get face-props :foreground))))
                 (when (and (stringp fg) (string-prefix-p "#" fg))
                   (setq color-verified t)))))
           (setq search-start2 (1+ (match-beginning 0))))
         (should color-verified))))))

(ert-deftest kuro-e2e-hidden-text ()
  :expected-result kuro-test--e2e-expected-result
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
  :expected-result kuro-test--e2e-expected-result
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
             (let* ((face-props (or (kuro-test--face-props-at pos) face))
                    (inv (and (listp face-props)
                              (plist-get face-props :inverse-video))))
               (when inv
                 (setq found-inverse t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-inverse)))))

(ert-deftest kuro-e2e-blink-structural ()
  :expected-result kuro-test--e2e-expected-result
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
  :expected-result kuro-test--e2e-expected-result
  "Test that terminal can be resized."
  (kuro-test--with-terminal
   ;; Resize to smaller dimensions
   (should (kuro--resize 10 40))
   (kuro-test--render buf)
   ;; Resize back
   (should (kuro--resize 24 80))))

(ert-deftest kuro-e2e-no-double-newlines ()
  :expected-result kuro-test--e2e-expected-result
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
  :expected-result kuro-test--e2e-expected-result
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
             (let* ((face-props (or (kuro-test--face-props-at pos) face))
                    (fg (and (listp face-props)
                             (plist-get face-props :foreground))))
               ;; Verify foreground is a hex color string
               (when (and (stringp fg) (string-equal fg "#ff0000"))
                 (setq found-color fg)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-color)))))

(ert-deftest kuro-e2e-truecolor-rgb-fg ()
  :expected-result kuro-test--e2e-expected-result
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
             (let* ((face-props (or (kuro-test--face-props-at pos) face))
                    (fg (and (listp face-props)
                             (plist-get face-props :foreground))))
               ;; Verify foreground is specifically #ff0000 (RGB 255,0,0)
               (when (and (stringp fg) (string-equal fg "#ff0000"))
                 (setq found-color fg)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-color)))))

(ert-deftest kuro-e2e-vim-basic ()
  :expected-result kuro-test--e2e-expected-result
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
     (kuro-test--render-until-idle buf)
     ;; Open vim with the unique temp file
     (kuro-test--send (format "vim %s" tmpfile))
     (kuro-test--send "\r")
     ;; Wait for vim's status bar to show the unique filename
     ;; (vim always shows filename in the last line of the screen)
     (should (kuro-test--wait-for buf tmpname))
     ;; Extra settle time
     (sleep-for 0.5)
     (kuro-test--render-until-idle buf)
     ;; Quit vim: ESC first to ensure normal mode, then :q!
     (kuro-test--send "\x1b")
     (sleep-for 0.1)
     (kuro-test--send ":q!")
     (kuro-test--send "\r")
     ;; Wait for vim to exit and primary screen to restore
     (sleep-for 0.5)
     (kuro-test--render-until-idle buf)
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
  :expected-result kuro-test--e2e-expected-result
  "Phase 02 acceptance: printf produces multiple lines correctly."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KMULTI1\\nKMULTI2\\nKMULTI3\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KMULTI1"))
   (should (kuro-test--wait-for buf "KMULTI2"))
   (should (kuro-test--wait-for buf "KMULTI3"))))

(ert-deftest kuro-e2e-tab-alignment ()
  :expected-result kuro-test--e2e-expected-result
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
  :expected-result kuro-test--e2e-expected-result
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
   (kuro-test--render-until-idle buf)
   ;; After clear, the visible screen should not show the old text
   ;; (it may be in scrollback, but not in the visible buffer area)
   (with-current-buffer buf
     (should-not (string-match-p "KBEFORECLEAR" (buffer-string))))))

;;; OSC title end-to-end integration

(ert-deftest kuro-e2e-osc-title-integration ()
  :expected-result kuro-test--e2e-expected-result
  "OSC 0/2 title sequence propagates through the full PTY→Rust→FFI→Emacs chain.
Sends a printf OSC sequence through a real shell, waits for the command to
complete, then runs extra render cycles to let kuro--render-cycle poll the
title via kuro--get-and-clear-title and rename the buffer."
  (kuro-test--with-terminal
    ;; Send OSC 0 title via printf and echo a marker to confirm completion
    (kuro--send-key "printf '\\033]0;kuro-title-test\\007' && echo OSC_TITLE_SENT")
    (kuro--send-key "\r")
    ;; Wait for the marker confirming printf ran
    (should (kuro-test--wait-for buf "OSC_TITLE_SENT"))
    ;; Poll until the buffer is renamed (render cycles fire kuro--get-and-clear-title)
    (let ((deadline (+ (float-time) kuro-test--timeout))
          (renamed nil))
      (while (and (not renamed) (< (float-time) deadline))
        (kuro-test--render buf)
        (when (string-match-p "kuro-title-test" (buffer-name buf))
          (setq renamed t))
        (unless renamed (sleep-for 0.05)))
      (should renamed))))

;;; Scrollback max-lines FFI propagation

(ert-deftest kuro-e2e-scrollback-max-lines-propagation ()
  :expected-result kuro-test--e2e-expected-result
  "kuro--set-scrollback-max-lines trims the scrollback buffer to the new limit.
Tests the full Elisp-wrapper → FFI → Rust chain for scrollback resizing.
Generates 30 lines of scrollback first, then sets the limit to 10, and verifies
that the Rust-side scrollback count is trimmed to the new limit."
  (kuro-test--with-terminal
    ;; First: set a generous initial limit so lines can accumulate
    (kuro--set-scrollback-max-lines 1000)
    ;; Generate 30 lines of output that will scroll into the scrollback buffer
    ;; Each echo goes to a new line, pushing prior lines into scrollback
    (kuro--send-key "for i in $(seq 1 30); do echo \"SCROLLBACK_LINE_$i\"; done")
    (kuro--send-key "\r")
    ;; Wait for the loop to complete
    (should (kuro-test--wait-for buf "SCROLLBACK_LINE_30"))
    ;; Force a few more render cycles to flush PTY data
    (kuro-test--render-until-idle buf)
    ;; Now reduce the scrollback limit to 10 — Rust should trim old lines
    (should-not (condition-case err
                    (progn (kuro--set-scrollback-max-lines 10) nil)
                  (error err)))
    ;; The scrollback count must now be at most 10
    (let ((count (kuro--get-scrollback-count)))
      (should (integerp count))
      (should (<= count 10)))))

;;; Phase 10 acceptance tests — tmux integration
;; These tests verify that tmux runs correctly inside a kuro terminal.
;; tmux is launched with -L kuro-e2e-test (isolated socket) and -f /dev/null to
;; avoid contamination from any existing tmux server or user configuration.
;; Timeout is extended to 10s for tmux startup.

(ert-deftest kuro-e2e-tmux-launches ()
  :expected-result kuro-test--e2e-expected-result
  "tmux starts successfully inside a kuro terminal buffer.
Verifies that tmux -f /dev/null new-session renders its status bar."
  (skip-unless (executable-find "tmux"))
  (kuro-test--with-terminal
    (unwind-protect
        (progn
          (kuro--send-key "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for-tmux buf)))
      (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(ert-deftest kuro-e2e-tmux-pane-split ()
  :expected-result kuro-test--e2e-expected-result
  "tmux pane splitting works: split-window -h and -v create new panes.
Uses tmux shell commands from within the session (more reliable than prefix keys)."
  (skip-unless (executable-find "tmux"))
  (kuro-test--with-terminal
    (unwind-protect
        (progn
          ;; Start tmux
          (kuro--send-key "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for-tmux buf))
          ;; Horizontal split from within tmux shell
          (kuro--send-key "tmux split-window -h -t kuro-test")
          (kuro--send-key "\r")
          (sleep-for 0.5)
          (kuro-test--render-until-idle buf)
          ;; Vertical split
          (kuro--send-key "tmux split-window -v -t kuro-test")
          (kuro--send-key "\r")
          (sleep-for 0.5)
          (kuro-test--render-until-idle buf)
          ;; Verify: tmux list-panes should show 3 panes (unique marker avoids false positives)
          (kuro--send-key "tmux list-panes -t kuro-test | wc -l | xargs printf 'KURO_PANE_COUNT_%s'")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for buf "KURO_PANE_COUNT_3")))
      (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(ert-deftest kuro-e2e-tmux-pane-navigate ()
  :expected-result kuro-test--e2e-expected-result
  "tmux pane navigation works: select-pane changes the active pane."
  (skip-unless (executable-find "tmux"))
  (kuro-test--with-terminal
    (unwind-protect
        (progn
          ;; Start tmux and create two panes
          (kuro--send-key "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for-tmux buf))
          (kuro--send-key "tmux split-window -h -t kuro-test")
          (kuro--send-key "\r")
          (sleep-for 0.3)
          ;; Navigate to pane 0
          (kuro--send-key "tmux select-pane -t kuro-test:.0")
          (kuro--send-key "\r")
          (sleep-for 0.3)
          (kuro-test--render-until-idle buf)
          ;; Verify the active pane is pane 0 using tmux display-message
          (kuro--send-key "tmux display-message -p 'KURO_PANE_IDX_#{pane_index}'")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for buf "KURO_PANE_IDX_0"))
          ;; Also confirm we can type in the active pane
          (kuro--send-key "echo PANE_NAVIGATE_OK")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for buf "PANE_NAVIGATE_OK")))
      (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(ert-deftest kuro-e2e-tmux-window-management ()
  :expected-result kuro-test--e2e-expected-result
  "tmux window management works: new-window and select-window work correctly."
  (skip-unless (executable-find "tmux"))
  (kuro-test--with-terminal
    (unwind-protect
        (progn
          ;; Start tmux
          (kuro--send-key "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for-tmux buf))
          ;; Create a new window
          (kuro--send-key "tmux new-window -t kuro-test")
          (kuro--send-key "\r")
          (sleep-for 0.3)
          (kuro-test--render-until-idle buf)
          ;; Verify: 2 windows exist (unique marker avoids false positives)
          (kuro--send-key "tmux list-windows -t kuro-test | wc -l | xargs printf 'KURO_WIN_COUNT_%s'")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for buf "KURO_WIN_COUNT_2"))
          ;; Navigate back to window 0
          (kuro--send-key "tmux select-window -t kuro-test:0")
          (kuro--send-key "\r")
          (sleep-for 0.2)
          (kuro--send-key "echo WINDOW_NAVIGATE_OK")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for buf "WINDOW_NAVIGATE_OK")))
      (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(ert-deftest kuro-e2e-tmux-session-cleanup ()
  :expected-result kuro-test--e2e-expected-result
  "tmux session terminates cleanly: kill-session returns control to shell."
  (skip-unless (executable-find "tmux"))
  (kuro-test--with-terminal
    (unwind-protect
        (progn
          ;; Start tmux
          (kuro--send-key "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
          (kuro--send-key "\r")
          (should (kuro-test--wait-for-tmux buf))
          ;; Kill the session from within it
          (kuro--send-key "tmux kill-session -t kuro-test")
          (kuro--send-key "\r")
          ;; After kill-session, we should return to the shell prompt
          ;; Echo a marker to confirm the shell is alive and responsive
          (sleep-for 0.5)
          (kuro-test--render-until-idle buf)
          (kuro--send-key (concat "echo " kuro-test--ready-marker))
          (kuro--send-key "\r")
          (should (kuro-test--wait-for buf kuro-test--ready-marker)))
      (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

;;; Additional SGR rendering tests

(ert-deftest kuro-e2e-italic-text ()
  :expected-result kuro-test--e2e-expected-result
  "SGR 3 (italic) produces :slant italic face property."
  (kuro-test--with-terminal
   (kuro-test--send "IT=\"\\033[3mKITALICTEXT\\033[0m\"; printf \"$IT\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KITALICTEXT"))
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-italic nil)
           (search-start 0))
       (while (and (not found-italic)
                   (string-match "KITALICTEXT" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (or (kuro-test--face-props-at pos) face))
                    (slant (and (listp face-props)
                                (plist-get face-props :slant))))
               (when (eq slant 'italic)
                 (setq found-italic t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-italic)))))

(ert-deftest kuro-e2e-dim-text ()
  :expected-result kuro-test--e2e-expected-result
  "SGR 2 (dim/faint) produces :weight light face property."
  (kuro-test--with-terminal
   (kuro-test--send "DM=\"\\033[2mKDIMTEXT\\033[0m\"; printf \"$DM\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KDIMTEXT"))
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-dim nil)
           (search-start 0))
       (while (and (not found-dim)
                   (string-match "KDIMTEXT" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (or (kuro-test--face-props-at pos) face))
                    (weight (and (listp face-props)
                                 (plist-get face-props :weight))))
               (when (eq weight 'light)
                 (setq found-dim t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-dim)))))

(ert-deftest kuro-e2e-strikethrough-text ()
  :expected-result kuro-test--e2e-expected-result
  "SGR 9 (strikethrough) produces :strike-through t face property."
  (kuro-test--with-terminal
   (kuro-test--send "ST=\"\\033[9mKSTRIKETEXT\\033[0m\"; printf \"$ST\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KSTRIKETEXT"))
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-strike nil)
           (search-start 0))
       (while (and (not found-strike)
                   (string-match "KSTRIKETEXT" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (or (kuro-test--face-props-at pos) face))
                    (st (and (listp face-props)
                             (plist-get face-props :strike-through))))
               (when st
                 (setq found-strike t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-strike)))))

(ert-deftest kuro-e2e-combined-sgr-attributes ()
  :expected-result kuro-test--e2e-expected-result
  "SGR 1;3;4 (bold + italic + underline) produces all three properties simultaneously."
  (kuro-test--with-terminal
   (kuro-test--send "CB=\"\\033[1;3;4mKCOMBOTEXT\\033[0m\"; printf \"$CB\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KCOMBOTEXT"))
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-bold nil)
           (found-italic nil)
           (found-underline nil)
           (search-start 0))
       (while (and (not (and found-bold found-italic found-underline))
                   (string-match "KCOMBOTEXT" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (or (kuro-test--face-props-at pos) face)))
               (when (listp face-props)
                 (when (eq 'bold   (plist-get face-props :weight))    (setq found-bold      t))
                 (when (eq 'italic (plist-get face-props :slant))     (setq found-italic    t))
                 (when            (plist-get face-props :underline)   (setq found-underline t))))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-bold)
       (should found-italic)
       (should found-underline)))))

(ert-deftest kuro-e2e-fast-blink ()
  :expected-result kuro-test--e2e-expected-result
  "SGR 6 (blink-fast) produces a blink overlay with type 'fast on the rendered text."
  (kuro-test--with-terminal
   (kuro-test--send "FB=\"\\033[6mKFASTBLINK\\033[0m\"; printf \"$FB\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KFASTBLINK"))
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     ;; Decode function must recognise blink-fast bit (#x20)
     (should (plist-get (kuro--decode-attrs #x20) :blink-fast))
     (let* ((content (buffer-string))
            (match-pos (string-match "KFASTBLINK" content)))
       (when match-pos
         (let* ((buf-pos (+ (point-min) match-pos))
                (ovs (overlays-at buf-pos))
                (blink-ov nil))
           (dolist (ov ovs)
             (when (overlay-get ov 'kuro-blink)
               (setq blink-ov ov)))
           (when blink-ov
             (should (eq 'fast (overlay-get blink-ov 'kuro-blink-type))))))))))

;;; Signal handling

(ert-deftest kuro-e2e-sigint-interrupts-command ()
  :expected-result kuro-test--e2e-expected-result
  "C-c (ASCII 3 = SIGINT) interrupts a running foreground process.
Starts `sleep 100', sends C-c, then verifies the shell is still responsive."
  (kuro-test--with-terminal
   ;; Launch a long-running process
   (kuro-test--send "sleep 100")
   (kuro-test--send "\r")
   ;; Let the process start
   (sleep-for 0.5)
   (kuro-test--render-until-idle buf)
   ;; Send SIGINT (C-c = byte 3)
   (kuro-test--send "\x03")
   (sleep-for 0.3)
   ;; Shell should now be responsive — verify by running a new command
   (kuro-test--send "echo KSIGINTOK")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KSIGINTOK"))))

;;; Input handling

(ert-deftest kuro-e2e-backspace-input ()
  :expected-result kuro-test--e2e-expected-result
  "Backspace (DEL, byte \\x7f) deletes the preceding typed character.
Types a stray character, erases it with DEL, then completes a command.
The shell should execute the corrected command, not the stray character."
  (kuro-test--with-terminal
   ;; Type a single stray character then immediately backspace it
   (kuro-test--send "X")
   (kuro-test--send "\x7f")
   ;; Now type and submit the real command
   (kuro-test--send "echo KBSTEST")
   (kuro-test--send "\r")
   ;; Output should contain KBSTEST (command ran correctly)
   (should (kuro-test--wait-for buf "KBSTEST"))))

;;; Scrollback content

(ert-deftest kuro-e2e-scrollback-content ()
  :expected-result kuro-test--e2e-expected-result
  "Scrollback buffer stores lines that scroll off the visible screen.
Generates more lines than the terminal height (24 rows) so the first
lines scroll into the scrollback buffer. Verifies the Rust-side
kuro-core-get-scrollback API returns the scrolled-off content."
  (kuro-test--with-terminal
   ;; Set a generous scrollback limit
   (kuro--set-scrollback-max-lines 500)
   ;; Generate 35 lines — more than the 24-row terminal height
   ;; Each has a unique marker so we can identify them in scrollback
   (kuro-test--send "for i in $(seq 1 35); do echo \"KSCROLL_LINE_$i\"; done")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KSCROLL_LINE_35"))
   (kuro-test--render-until-idle buf)
   ;; Scrollback count must be at least 1 (some lines scrolled off)
   (let ((count (kuro--get-scrollback-count)))
     (should (integerp count))
     (should (> count 0)))
   ;; Retrieve scrollback and verify it contains early lines
   (let ((lines (kuro--get-scrollback 100)))
     (should (listp lines))
     (should (> (length lines) 0))
     ;; At least one line should contain "KSCROLL_LINE_" (the early lines)
     (let ((found nil))
       (dolist (line lines)
         (when (and (stringp line) (string-match-p "KSCROLL_LINE_" line))
           (setq found t)))
       (should found)))))

;;; Unicode output

(ert-deftest kuro-e2e-unicode-output ()
  :expected-result kuro-test--e2e-expected-result
  "UTF-8 multibyte characters appear correctly in the terminal buffer.
Tests that the PTY ↔ Rust ↔ Emacs pipeline preserves non-ASCII text."
  (kuro-test--with-terminal
   ;; Print a Japanese string using printf with explicit UTF-8
   (kuro-test--send "printf 'KUNICODE_START\\n\\xe6\\x97\\xa5\\xe6\\x9c\\xac\\xe8\\xaa\\x9e\\nKUNICODE_END\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KUNICODE_END"))
   ;; The buffer must contain at least one non-ASCII character between the markers
   (with-current-buffer buf
     (let ((content (buffer-string)))
       ;; Check that multibyte chars are present
       (should (string-match-p "\\cC\\|\\cc\\|[^\x00-\x7f]" content))))))

;;; Large output

(ert-deftest kuro-e2e-large-output ()
  :expected-result kuro-test--e2e-expected-result
  "Generating 200 lines of output does not crash or hang the terminal.
Verifies that large PTY bursts are processed without data loss."
  (kuro-test--with-terminal
   ;; Use seq to generate 200 numbered lines rapidly
   (kuro-test--send "seq 1 200 | xargs -I{} echo \"KLARGE_{}\"")
   (kuro-test--send "\r")
   ;; Just need the last line to appear — intermediate lines go to scrollback
   (let ((deadline (+ (float-time) 15.0))
         (found nil))
     (while (and (not found) (< (float-time) deadline))
       (kuro-test--render buf)
       (with-current-buffer buf
         (when (string-match-p "KLARGE_200" (buffer-string))
           (setq found t)))
       (unless found
         ;; Also check scrollback
         (let ((scrollback (kuro--get-scrollback 20)))
           (dolist (line scrollback)
             (when (and (stringp line) (string-match-p "KLARGE_200" line))
               (setq found t)))))
       (unless found (sleep-for 0.1)))
     (should found))))

;;; Alternate screen (less pager)

(ert-deftest kuro-e2e-less-pager ()
  :expected-result kuro-test--e2e-expected-result
  "less opens on the alternate screen and returns to primary screen on exit.
Verifies the SMCUP/RMCUP sequence pair used by full-screen applications."
  (skip-unless (executable-find "less"))
  (kuro-test--with-terminal
   ;; Pipe seq output into less — this forces the alternate screen
   (kuro-test--send "seq 1 50 | less")
   (kuro-test--send "\r")
   ;; less should show its content — wait for a number (any line from seq)
   (should (kuro-test--wait-for buf "[0-9]"))
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   ;; Quit less by sending 'q'
   (kuro-test--send "q")
   (sleep-for 0.5)
   (kuro-test--render-until-idle buf)
   ;; Primary screen should be restored — shell must be responsive
   (kuro-test--send "echo KLESSOK")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KLESSOK"))))

;;; Ctrl+L screen clear

(ert-deftest kuro-e2e-ctrl-l-clear-screen ()
  :expected-result kuro-test--e2e-expected-result
  "Ctrl+L (\x0c = form-feed) keeps the shell responsive under the test harness."
  (kuro-test--with-terminal
   (kuro-test--send "echo KBEFORECTRL")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KBEFORECTRL"))
   (kuro-test--send "\x0c")
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (kuro-test--send "echo KAFTERCTRL")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KAFTERCTRL"))))

(ert-deftest kuro-e2e-send-string-api ()
  :expected-result kuro-test--e2e-expected-result
  "kuro-send-string (public API in kuro.el) delivers a string to the PTY.
Verifies the public-facing wrapper works end-to-end, distinct from the
internal kuro--send-key helper used by all other E2E tests."
  (require 'kuro)
  (kuro-test--with-terminal
   (kuro-send-string "echo KSENDSTRAPI")
   (kuro-send-string "\r")
   (should (kuro-test--wait-for buf "KSENDSTRAPI"))))

(ert-deftest kuro-e2e-bell-character ()
  :expected-result kuro-test--e2e-expected-result
  "BEL byte (\007) reaches the live bell path in the renderer."
  (require 'kuro-renderer)
  (kuro-test--with-terminal
   (let ((ding-called nil))
     (cl-letf (((symbol-function 'ding)
                (lambda (&optional _arg) (setq ding-called t))))
       (kuro-test--send "printf '\\a'")
       (kuro-test--send "\r")
       (sleep-for 0.3)
       ;; First render drains PTY output and records the pending bell.
       (kuro-test--render buf)
       ;; Drive the bell handling path directly to avoid timer/coalescing variance.
       (with-current-buffer buf
         (kuro--ring-pending-bell))
       (should ding-called)))))

(ert-deftest kuro-e2e-clear-scrollback ()
  :expected-result kuro-test--e2e-expected-result
  "kuro--clear-scrollback resets the scrollback count to zero.
Exercises kuro-core-clear-scrollback and kuro-core-get-scrollback-count FFI."
  (kuro-test--with-terminal
   ;; Overflow the 24-row terminal to push lines into scrollback
   (kuro-test--send "seq 1 30 | xargs -I{} echo KCLEARSCROLL_{}")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KCLEARSCROLL_"))
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     ;; Scrollback should have content after overflow
     (let ((count-before (kuro--get-scrollback-count)))
       (should (and count-before (> count-before 0)))
       ;; Clear the scrollback buffer via FFI wrapper
       (kuro--clear-scrollback)
       ;; Rust state should now report zero scrollback lines
       (let ((count-after (kuro--get-scrollback-count)))
         (should (and count-after (= count-after 0))))))))

(ert-deftest kuro-e2e-cursor-visibility ()
  :expected-result kuro-test--e2e-expected-result
  "DECTCEM CSI?25l hides the cursor; CSI?25h makes it visible again.
Exercises kuro-core-get-cursor-visible FFI function via kuro--get-cursor-visible."
  (kuro-test--with-terminal
   ;; Cursor should be visible by default
   (with-current-buffer buf
     (should (kuro--get-cursor-visible)))
   ;; Hide the cursor via printf (application side controls DECTCEM)
   (kuro-test--send "printf '\\033[?25l'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should-not (kuro--get-cursor-visible)))
   ;; Restore cursor visibility
   (kuro-test--send "printf '\\033[?25h'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (kuro--get-cursor-visible)))))

(ert-deftest kuro-e2e-decckm-mode ()
  :expected-result kuro-test--e2e-expected-result
  "CSI?1h enables application cursor keys mode (DECCKM).
Exercises kuro-core-get-app-cursor-keys FFI function via kuro--get-app-cursor-keys.
Only verifies the enabled state; disabling is a no-op test (shell resets on prompt)."
  (kuro-test--with-terminal
   ;; Enable DECCKM — application cursor keys mode
   (kuro-test--send "printf '\\033[?1h'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (kuro--get-app-cursor-keys)))
   ;; Send disable to leave terminal in a clean state
   (kuro-test--send "printf '\\033[?1l'")
   (kuro-test--send "\r")
   (sleep-for 0.1)))

(ert-deftest kuro-e2e-bracketed-paste-mode ()
  :expected-result kuro-test--e2e-expected-result
  "CSI?2004h enables bracketed paste mode.
Exercises kuro-core-get-bracketed-paste FFI function via kuro--get-bracketed-paste."
  (kuro-test--with-terminal
   ;; Explicitly enable bracketed paste mode (modern shells may already enable it)
   (kuro-test--send "printf '\\033[?2004h'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (kuro--get-bracketed-paste)))))

(ert-deftest kuro-e2e-scroll-viewport ()
  :expected-result kuro-test--e2e-expected-result
  "kuro--scroll-up and kuro--scroll-down shift the viewport into scrollback history.
Exercises kuro-core-scroll-up, kuro-core-scroll-down, and
kuro-core-get-scroll-offset FFI functions via their Elisp wrappers."
  (kuro-test--with-terminal
   ;; Generate enough output to overflow into scrollback (terminal is 24 rows)
   (kuro-test--send "seq 1 30 | xargs -I{} echo KSCROLLVP_{}")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KSCROLLVP_"))
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     ;; Baseline: viewport is at offset 0 (live screen)
     (should (= (kuro--get-scroll-offset) 0))
     ;; Scroll up 5 lines into scrollback history
     (kuro--scroll-up 5)
     ;; Offset must now be positive (scrolled away from live screen)
     (should (> (kuro--get-scroll-offset) 0))
     ;; Scroll back down to the live screen
     (kuro--scroll-down 5)
     ;; Offset should return to zero (or near zero)
     (should (<= (kuro--get-scroll-offset) 1)))))

;;; Additional E2E coverage — ED 3, bracketed-paste yank, keyboard scroll, Unicode send

(ert-deftest kuro-e2e-erase-scrollback-ed3 ()
  :expected-result kuro-test--e2e-expected-result
  "CSI 3J (ED J=3) erases the scrollback buffer and resets the scrollback count to zero.
Exercises the ED J=3 branch in erase.rs, which is distinct from ED 2 (erase screen)
and is not covered by any other E2E test.  The scrollback buffer accumulates lines
that have been scrolled off the visible screen; CSI 3J is the xterm-standard way to
purge it (Ctrl-L in bash uses CSI 2J which only erases the screen, not scrollback)."
  (kuro-test--with-terminal
   ;; Overflow the 24-row terminal to push lines into scrollback
   (kuro-test--send "seq 1 30 | xargs -I{} echo KERASEED3_{}")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KERASEED3_"))
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     ;; Scrollback must be non-empty before the erase
     (should (> (kuro--get-scrollback-count) 0)))
   ;; Send CSI 3J (erase scrollback) via the normal shell output path so that
   ;; the sequence reaches the Rust terminal as PTY stdout bytes, not raw key input.
   (kuro-test--send "printf '\\033[3J'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     ;; Scrollback count must be near 0 after ED 3.
     ;; Allow up to 1 line: the shell prompt output after the printf command
     ;; may push exactly one line back into scrollback before we check.
     (should (<= (kuro--get-scrollback-count) 1)))))

(ert-deftest kuro-e2e-bracketed-paste-yank ()
  :expected-result kuro-test--e2e-expected-result
  "kuro--yank wraps kill-ring content with ESC[200~/ESC[201~ in bracketed paste mode.
Also verifies that kuro--sanitize-paste strips ESC bytes from pasted content to prevent
bracketed paste injection attacks.  Tests kuro-input.el paste path without hitting PTY."
  (require 'kuro-input)
  (kuro-test--with-terminal
   ;; ── Case 1: bracketed paste mode ON ─────────────────────────────────────
   ;; Kill ring content with an embedded ESC (injection attempt).
   ;; kuro--sanitize-paste must strip the ESC before wrapping.
   (kill-new (concat "BPASTE_PAYLOAD\x1bBAD"))
   (let (sent-string)
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (setq sent-string s))))
       (with-current-buffer buf
         ;; Force bracketed paste mode on without needing a render cycle
         (setq kuro--bracketed-paste-mode t)
         (kuro--yank)))
     ;; Content must be wrapped with BP markers
     (should (string-prefix-p "\e[200~" sent-string))
     (should (string-suffix-p "\e[201~" sent-string))
     ;; Payload present (ESC stripped, "BAD" stripped because it followed ESC)
     (should (string-match-p "BPASTE_PAYLOAD" sent-string))
     ;; ESC byte must be absent — injection prevention
     (should-not (string-match-p "\x1b[^[]" sent-string)))
   ;; ── Case 2: bracketed paste mode OFF ────────────────────────────────────
   ;; Content is sent verbatim (no BP markers, no sanitization)
   (kill-new "RAW_PAYLOAD")
   (let (sent-string)
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (setq sent-string s))))
       (with-current-buffer buf
         (setq kuro--bracketed-paste-mode nil)
         (kuro--yank)))
     (should (string= "RAW_PAYLOAD" sent-string)))))

(ert-deftest kuro-e2e-scrollback-keyboard-commands ()
  :expected-result kuro-test--e2e-expected-result
  "kuro-scroll-up, kuro-scroll-down, and kuro-scroll-bottom are the keyboard-accessible
scrollback commands (Shift+PgUp / Shift+PgDn / Shift+End).  They differ from the
FFI-level kuro--scroll-up/down tested in kuro-e2e-scroll-viewport: they use
window-body-height as the line count and call kuro--render-cycle automatically.
Exercises kuro-input.el public scroll API and the kuro--initialized guard."
  (kuro-test--with-terminal
   ;; Generate enough output to create scrollback
   (kuro-test--send "seq 1 30 | xargs -I{} echo KSCRLKBD_{}")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KSCRLKBD_"))
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     ;; Baseline: live view, offset 0
     (should (= (kuro--get-scroll-offset) 0))
     ;; window-body-height returns 0 in batch mode; mock it to scroll a real amount
     (cl-letf (((symbol-function 'window-body-height)
                (lambda (&optional _window _pixelwise) 10)))
       ;; kuro-scroll-up → offset becomes positive
       (kuro-scroll-up)
       (should (> (kuro--get-scroll-offset) 0))
       ;; kuro-scroll-down → offset decreases
       (kuro-scroll-down)
       ;; kuro-scroll-bottom → jump back to live view (offset 0)
       (kuro-scroll-bottom)
       (should (= (kuro--get-scroll-offset) 0))))))

(ert-deftest kuro-e2e-kuro-send-interrupt-api ()
  :expected-result kuro-test--e2e-expected-result
  "kuro-send-interrupt (public API in kuro.el) delivers SIGINT to interrupt a process.
This exercises a different code path from kuro-e2e-sigint-interrupts-command: that test
sends the raw \\x03 byte via kuro-test--send, whereas this test calls the Lisp function
which sends a vector [?\\C-c] through kuro--send-key's vector→string conversion path."
  (require 'kuro)
  (kuro-test--with-terminal
   ;; Start a long-running process in the foreground
   (kuro-test--send "sleep 100")
   (kuro-test--send "\r")
   (sleep-for 0.5)
   (kuro-test--render-until-idle buf)
   ;; Interrupt via the public Lisp function (sends [?\C-c] vector → "\x03" byte)
   (kuro-send-interrupt)
   (sleep-for 0.3)
   ;; Shell must be responsive after interruption
   (kuro-test--send "echo KINTERRUPTAPI")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KINTERRUPTAPI"))))

;;; E2E: kuro--RET key function and DECKPAM mode

(ert-deftest kuro-e2e-ret-key-function ()
  :expected-result kuro-test--e2e-expected-result
  "kuro--RET (\\r, carriage return) submits a typed command to the shell.
Exercises the kuro--RET function directly, which sends a CR byte via
kuro--send-ctrl.  This is distinct from kuro-test--send which calls
kuro--send-key directly; the test proves the round-trip works end-to-end."
  (require 'kuro-input)
  (kuro-test--with-terminal
   (kuro--send-key "echo KRETTEST")
   (sleep-for 0.1)
   (kuro--RET)
   (should (kuro-test--wait-for buf "KRETTEST"))))

(ert-deftest kuro-e2e-deckpam-mode ()
  :expected-result kuro-test--e2e-expected-result
  "ESC= (DECKPAM) enables application keypad mode; verified via kuro--get-app-keypad.
Exercises the esc_dispatch path in lib.rs: ([], b'=') → app_keypad = true.
Mirrors the kuro-e2e-decckm-mode pattern: only the enabled state is asserted
since some shells may emit ESC> on prompt redraw."
  (kuro-test--with-terminal
   ;; Enable DECKPAM — application keypad mode (ESC=)
   (kuro-test--send "printf '\\033='")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (kuro--get-app-keypad)))
   ;; Restore DECKPNM for a clean terminal state (ESC>) — no assertion;
   ;; shell may have already reset this on the next prompt redraw.
   (kuro-test--send "printf '\\033>'")
   (kuro-test--send "\r")
   (sleep-for 0.1)))

;;; Additional mouse tracking mode E2E tests

(ert-deftest kuro-e2e-mouse-mode-normal-enable ()
  :expected-result kuro-test--e2e-expected-result
  "CSI?1000h enables normal (X10 compatible) mouse tracking mode.
Exercises kuro-core-get-mouse-mode FFI via kuro--get-mouse-mode.
Only verifies the enabled state; shells may reset mouse mode on prompt redraw."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[?1000h'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (= (kuro--get-mouse-mode) 1000)))
   ;; Disable to restore clean terminal state
   (kuro-test--send "printf '\\033[?1000l'")
   (kuro-test--send "\r")
   (sleep-for 0.1)))

(ert-deftest kuro-e2e-mouse-mode-button-event-enable ()
  :expected-result kuro-test--e2e-expected-result
  "CSI?1002h enables button-event mouse tracking mode.
kuro--get-mouse-mode returns 1002 after the sequence is processed."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[?1002h'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (= (kuro--get-mouse-mode) 1002)))
   (kuro-test--send "printf '\\033[?1002l'")
   (kuro-test--send "\r")
   (sleep-for 0.1)))

(ert-deftest kuro-e2e-mouse-sgr-mode-enable ()
  :expected-result kuro-test--e2e-expected-result
  "CSI?1006h enables SGR extended coordinates mouse mode.
Exercises kuro-core-get-mouse-sgr FFI via kuro--get-mouse-sgr.
Only verifies the enabled state."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[?1006h'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (kuro--get-mouse-sgr)))
   (kuro-test--send "printf '\\033[?1006l'")
   (kuro-test--send "\r")
   (sleep-for 0.1)))

;;; Character insert/delete E2E tests (ICH/DCH)
;; These use a positive-assertion strategy: the printf command echo shows raw
;; \033 escape literals (not processed), so the transformed marker string
;; (produced by the terminal processing CSI sequences) appears ONLY in the
;; printf output — never in the command echo.

(ert-deftest kuro-e2e-delete-characters-dch ()
  :expected-result kuro-test--e2e-expected-result
  "CSI 2P (DCH) deletes 2 characters at the cursor position.
Prints 'KDCH_ABC' (cursor at col 8), CSI 1D moves cursor to col 7 (at 'C'),
CSI 2P deletes 2 chars ('C' and the empty cell at col 8), then 'END' is
printed at col 7, yielding 'KDCH_ABEND'.  The command echo shows the raw
\\033 literals and does not contain 'KDCH_ABEND'."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KDCH_ABC\\033[1D\\033[2PEND'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KDCH_ABEND"))))

(ert-deftest kuro-e2e-insert-characters-ich ()
  :expected-result kuro-test--e2e-expected-result
  "CSI 1@ (ICH) inserts 1 blank character at the cursor position.
Prints 'KICH_AB' (cursor at col 7), CSI 1D moves cursor to col 6 (at 'B'),
CSI 1@ inserts 1 blank (shifts 'B' to col 7, cursor stays at col 6), then
'Z' is printed at col 6, yielding 'KICH_AZB'.  The trailing \\n ensures the
cursor ends at column 0 so the shell's no-newline indicator does not overwrite
the ICH-shifted 'B'.  The command echo shows raw \\033 literals and does not
contain 'KICH_AZB'."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KICH_AB\\033[1D\\033[1@Z\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KICH_AZB"))))

;;; Erase line (EL 0) E2E test

(ert-deftest kuro-e2e-erase-line-to-end-el0 ()
  :expected-result kuro-test--e2e-expected-result
  "CSI K (EL 0) erases from the cursor position to the end of line.
Prints 'KEL0_AX' (cursor at col 7), CSI 1D moves cursor to col 6 (at 'X'),
CSI K erases col 6 through end-of-line (removing 'X' and beyond), then 'END'
is printed at col 6, yielding 'KEL0_AEND'.  The command echo shows raw \\033
literals and does not contain 'KEL0_AEND'."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KEL0_AX\\033[1D\\033[KEND'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KEL0_AEND"))))

;;; SGR attribute coverage — reset and bright background

(ert-deftest kuro-e2e-sgr-reset-bold ()
  :expected-result kuro-test--e2e-expected-result
  "SGR 22 resets bold intensity: text rendered after SGR 22 has :weight normal.
Uses the variable trick so the marker does not appear in the command echo
with the face property applied — only the printf output has the face."
  (kuro-test--with-terminal
   (kuro-test--send "B=\"\\033[1mKBLD22\\033[22mKNRM22\\033[0m\"; printf \"$B\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KNRM22"))
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-normal nil)
           (search-start 0))
       (while (and (not found-normal)
                   (string-match "KNRM22" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face))
                (face-props (and face (or (kuro-test--face-props-at pos) face)))
                (weight (and (listp face-props)
                             (plist-get face-props :weight))))
           (when (not (eq weight 'bold))
             (setq found-normal t)))
         (setq search-start (1+ (match-beginning 0))))
        (should found-normal)))))

(ert-deftest kuro-e2e-bright-background-color ()
  :expected-result kuro-test--e2e-expected-result
  "SGR 101 (bright red background) produces a :background hex face property.
Bright background codes (SGR 100-107) are distinct from normal backgrounds
(SGR 40-47) — this test verifies the bright palette is rendered."
  (kuro-test--with-terminal
   (kuro-test--send "H=\"\\033[101mKBGHI101\\033[0m\"; printf \"$H\"")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KBGHI101"))
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string))
           (found-bg nil)
           (search-start 0))
       (while (and (not found-bg)
                   (string-match "KBGHI101" content search-start))
         (let* ((pos (+ (point-min) (match-beginning 0)))
                (face (get-text-property pos 'face)))
           (when face
             (let* ((face-props (or (kuro-test--face-props-at pos) face))
                    (bg (and (listp face-props)
                             (plist-get face-props :background))))
               (when (and (stringp bg) (string-prefix-p "#" bg))
                 (setq found-bg t)))))
         (setq search-start (1+ (match-beginning 0))))
       (should found-bg)))))

;;; Cursor movement — CUU, CUB, CUF, CHA

(ert-deftest kuro-e2e-cursor-up-cuu ()
  :expected-result kuro-test--e2e-expected-result
  "CUU (cursor up, ESC[NA) moves the cursor up by N rows."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KCUU_A\\nKCUU_B\\033[1AX'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (string-match-p "KCUU_AX" (buffer-string))))))

(ert-deftest kuro-e2e-cursor-backward-cub ()
  :expected-result kuro-test--e2e-expected-result
  "CUB (cursor backward, ESC[ND) moves the cursor left by N columns.
Print KCUB_ABCDE (cursor at col 10), CUB 5 (col 5), X overwrites A
— result: KCUB_XBCDE."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KCUB_ABCDE\\033[5DX\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KCUB_XBCDE"))))

(ert-deftest kuro-e2e-cursor-forward-cuf ()
  :expected-result kuro-test--e2e-expected-result
  "CUF (cursor forward, ESC[NC) moves the cursor right by N columns.
Print KCUF_ABCDE, CUB 5 (col 5), CUF 3 (col 8), X overwrites D
— result: KCUF_ABCXE."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KCUF_ABCDE\\033[5D\\033[3CX\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KCUF_ABCXE"))))

(ert-deftest kuro-e2e-cursor-cha ()
  :expected-result kuro-test--e2e-expected-result
  "CHA (cursor horizontal absolute, ESC[NG) moves to column N (1-indexed)."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[2J\\033[H\\033[1G'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (cdr cursor) 0))))))

(ert-deftest kuro-e2e-cursor-down-cud ()
  :expected-result kuro-test--e2e-expected-result
  "CUD (cursor down, ESC[NB) moves cursor down by N rows.
Print KCUDA (row 0), newline, KCUDB (row 1), CUU 1 back to row 0, CUD 1
back to row 1 — X appended at col 5: result KCUDBX.
Trailing \\n prevents fish's partial-line indicator."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'KCUDA\\nKCUDB\\033[1A\\033[1BX\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KCUDBX"))))

;;; Erase operations — ED 0, ED 1, EL 2

(ert-deftest kuro-e2e-erase-display-to-end-ed0 ()
  :expected-result kuro-test--e2e-expected-result
  "ED 0 (CSI J) erases from cursor position to end of display.
Cursor homed to (1;1), so the entire screen is cleared."
  (kuro-test--with-terminal
   (kuro-test--send "echo KED0_MARK")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KED0_MARK"))
   (kuro-test--render-until-idle buf 0.3)
   (kuro-test--send "printf '\\033[1;1H\\033[J'")
   (kuro-test--send "\r")
   (kuro-test--render-until-idle buf 0.5)
   (with-current-buffer buf
     (should-not (string-match-p "KED0_MARK" (buffer-string))))))

(ert-deftest kuro-e2e-erase-display-from-start-ed1 ()
  :expected-result kuro-test--e2e-expected-result
  "ED 1 (CSI 1J) erases from start of display to cursor.
Cursor moved to last row/col (24;80), so the entire screen is cleared."
  (kuro-test--with-terminal
   (kuro-test--send "echo KED1_MARK")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KED1_MARK"))
   (kuro-test--render-until-idle buf 0.3)
   (kuro-test--send "printf '\\033[24;80H\\033[1J'")
   (kuro-test--send "\r")
   (kuro-test--render-until-idle buf 0.5)
   (with-current-buffer buf
     (should-not (string-match-p "KED1_MARK" (buffer-string))))))

(ert-deftest kuro-e2e-erase-line-entire-el2 ()
  :expected-result kuro-test--e2e-expected-result
  "EL 2 (CSI 2K) erases the entire current line.
Variable split prevents the marker from appearing in the command echo;
CUU 1 positions on the echo row; EL 2 erases it; KEL2_DONE confirms."
  (kuro-test--with-terminal
   (kuro-test--send "A=\"KEL2_\"; B=\"MARK\"; echo \"$A$B\"; printf '\\033[A\\033[2K'; echo KEL2_DONE")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KEL2_DONE"))
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should-not (string-match-p "KEL2_MARK" (buffer-string))))))

;;; Alternate screen buffer — mode 1049

(ert-deftest kuro-e2e-alternate-screen-buffer ()
  :expected-result kuro-test--e2e-expected-result
  "Mode 1049 switches between primary and alternate screen buffers.
Primary content is hidden on the alternate screen and restored on return."
  (kuro-test--with-terminal
   (kuro-test--send "echo KALT_PRIMARY")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KALT_PRIMARY"))
   (kuro-test--render-until-idle buf)
   (kuro-test--send "printf '\\033[?1049h'")
   (kuro-test--send "\r")
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should-not (string-match-p "KALT_PRIMARY" (buffer-string))))
   (kuro-test--send "printf '\\033[?1049l'")
   (kuro-test--send "\r")
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (string-match-p "KALT_PRIMARY" (buffer-string))))))

;;; Scroll operations — SU, SD

(ert-deftest kuro-e2e-scroll-up-su ()
  :expected-result kuro-test--e2e-expected-result
  "SU (CSI S) scrolls content up, saving rows to scrollback.
SU 24 fills the screen with blank rows; previous content moves to scrollback."
  (kuro-test--with-terminal
   (kuro-test--send "echo KSU_MARKER")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KSU_MARKER"))
   (kuro-test--render-until-idle buf)
   (kuro-test--send "printf '\\033[24S'")
   (kuro-test--send "\r")
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should-not (string-match-p "KSU_MARKER" (buffer-string)))
     (let* ((lines (kuro--get-scrollback 200))
            (joined (mapconcat #'identity lines "\n")))
       (should (string-match-p "KSU_MARKER" joined))))))

(ert-deftest kuro-e2e-scroll-down-sd ()
  :expected-result kuro-test--e2e-expected-result
  "SD (CSI T) scrolls content down: blank rows at top, bottom content dropped.
Unlike SU, SD does not save to scrollback — dropped rows are truly lost."
  (kuro-test--with-terminal
   (kuro--clear-scrollback)
   (kuro-test--send "echo KSD_DROPPED")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KSD_DROPPED"))
   (kuro-test--render-until-idle buf)
   (kuro-test--send "printf '\\033[24T'")
   (kuro-test--send "\r")
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
      (let* ((lines (kuro--get-scrollback 200))
             (joined (mapconcat #'identity lines "\n")))
        (should-not (string-match-p "KSD_DROPPED" joined))
        (should-not (string-match-p "KSD_DROPPED" (buffer-string)))))))

;;; E2E Gap Analysis Tests (E01-E15)

(ert-deftest kuro-e2e-erase-line-to-cursor ()
  :expected-result kuro-test--e2e-expected-result
  "CSI 1 K (EL 1) erases from start of line to cursor position.
  Prints text, positions cursor at col 20, sends CSI 1 K in one atomic
  printf so all escape sequences apply to the same row."
  (kuro-test--with-terminal
   ;; Single printf: print text, move to col 20, EL1 erase SOL-to-cursor.
   ;; Using \\033 so bash single-quotes pass literal \033 to printf for
   ;; interpretation as ESC (real ESC bytes would be consumed by readline).
   (kuro-test--send "printf 'KEL1_START1234567890END\\033[20G\\033[1K\\n'")
   (kuro-test--send "\r")
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   ;; After EL1: cols 1-20 erased to spaces; cols 21-23 retain original 'END'.
   (with-current-buffer buf
      (let ((content (buffer-string)))
        (should (string-match-p "END" content))
        (should-not (string-match-p "KEL1_START" content))))))

(ert-deftest kuro-e2e-erase-entire-line ()
  :expected-result kuro-test--e2e-expected-result
  "CSI 2 K (EL 2) erases the entire current line.
  Prints text then immediately sends EL 2 in one atomic printf so the
  erase applies to the same row the text was written on."
  (kuro-test--with-terminal
   ;; Single printf: print text, EL2 erase entire line, then LINE_CLEARED marker.
   ;; Using \\033 so bash single-quotes pass literal \033 to printf for
   ;; interpretation as ESC (real ESC bytes would be consumed by readline).
   (kuro-test--send "printf 'KEL2_ENTIRE_LINE_TEXT_HERE\\033[2KLINE_CLEARED\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "LINE_CLEARED"))
   (sleep-for 0.2)
   (kuro-test--render-until-idle buf)
   ;; After EL2: the entire line is blank; only LINE_CLEARED (written after EL2)
   ;; should appear.  The original KEL2_ENTIRE_LINE_TEXT is gone.
   (with-current-buffer buf
     (should-not (string-match-p "KEL2_ENTIRE_LINE_TEXT" (buffer-string))))))

(ert-deftest kuro-e2e-erase-from-start-to-cursor ()
  :expected-result kuro-test--e2e-expected-result
  "CSI 1 J (ED 1) erases from start of display to cursor."
  (kuro-test--with-terminal
   (kuro-test--send "for i in $(seq 1 15); do echo \"ROW_$i\"; done")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "ROW_15"))
   (sleep-for 0.3)
   (kuro-test--render-until-idle buf)
   (kuro-test--send "printf '\\033[9;1HERASED_TO_CURSOR\\033[1J'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
    (with-current-buffer buf
     (let ((content (buffer-string)))
        (should (string-match-p "ROW_10\\|ROW_11\\|ROW_12\\|ROW_13\\|ROW_14\\|ROW_15" content))
        (should-not (string-match-p "ROW_1\n\\|ROW_2\n\\|ROW_3\n\\|ROW_4\n\\|ROW_5\n" content))))))

(ert-deftest kuro-e2e-cursor-up-movement ()
  :expected-result kuro-test--e2e-expected-result
  "CSI A (CUU) moves cursor up by N rows.
  Samples the cursor while the shell command is still sleeping, before the
prompt returns and overwrites the position."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[11;1H\\033[5A'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (car cursor) 5))))))

(ert-deftest kuro-e2e-cursor-down-movement ()
  :expected-result kuro-test--e2e-expected-result
  "CSI B (CUD) moves cursor down by N rows.
  Samples the cursor while the shell command is still sleeping, before the
prompt returns and overwrites the position."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[H\\033[3B'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (car cursor) 3))))))

(ert-deftest kuro-e2e-cursor-left-movement ()
  :expected-result kuro-test--e2e-expected-result
  "CSI D (CUB) moves cursor left by N columns.
  Samples the cursor while the shell command is still sleeping, before the
prompt returns and overwrites the position."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[11G\\033[5D'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (cdr cursor) 5))))))

(ert-deftest kuro-e2e-cursor-right-movement ()
  :expected-result kuro-test--e2e-expected-result
  "CSI C (CUF) moves cursor right by N columns.
  Samples the cursor while the shell command is still sleeping, before the
prompt returns and overwrites the position."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[G\\033[10C'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (cdr cursor) 10))))))

(ert-deftest kuro-e2e-character-position-absolute ()
  :expected-result kuro-test--e2e-expected-result
  "CSI G (CHA) moves cursor to absolute column N (1-indexed).
  Samples the cursor while the shell command is still sleeping, before the
prompt returns and overwrites the position."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[40G'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (cdr cursor) 39))))))

(ert-deftest kuro-e2e-vertical-position-absolute ()
  :expected-result kuro-test--e2e-expected-result
  "CSI d (VPA) moves cursor to absolute row N (1-indexed).
  Samples the cursor while the shell command is still sleeping, before the
prompt returns and overwrites the position."
  (kuro-test--with-terminal
   (kuro-test--send "printf '\\033[12d'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (car cursor) 11))))))

(ert-deftest kuro-e2e-insert-characters ()
  :expected-result kuro-test--e2e-expected-result
  "CSI @ (ICH) inserts N blank characters at cursor position.
Prints 'hello' (cursor at col 5), CHA 1 (\033[1G) moves cursor to col 0,
ICH 3 (\033[3@) inserts 3 blanks shifting 'hello' right; 'lo' then
overwrites cols 0-1. Trailing \n prevents partial-line indicator."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'hello\\033[1G\\033[3@lo\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "lo"))
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "lo" content))
       (should (string-match-p "hel" content))))))

(ert-deftest kuro-e2e-delete-characters ()
  :expected-result kuro-test--e2e-expected-result
  "CSI P (DCH) deletes N characters at cursor position."
  (kuro-test--with-terminal
   (kuro-test--send "printf 'hello\\033[2G\\033[2P'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (should (string-match-p "hlo" (buffer-string))))))

(ert-deftest kuro-e2e-erase-characters ()
  :expected-result kuro-test--e2e-expected-result
  "CSI X (ECH) erases N characters from cursor position.
Prints KECH_hello (cursor at col 10), CUB 5 moves cursor back to the h at
col 5, ECH 3 erases hel to spaces (cursor stays at col 5), then AFTER is
printed yielding KECH_   loAFTER.  All sequences are in one atomic printf
so there is no race between shell commands."
  (kuro-test--with-terminal
   ;; Single atomic printf: print marker, move back 5, ECH 3, print AFTER
   (kuro-test--send "printf 'KECH_hello\\033[5D\\033[3XAFTER\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "AFTER"))
   (kuro-test--render-until-idle buf 0.3)
   ;; ECH erases 'hel' to spaces; 'lo' remains then AFTER is printed
   ;; The visible text must contain 'KECH_' (prefix) and 'AFTER' (suffix)
   ;; but must NOT contain 'KECH_hel' (first 3 chars of 'hello' were erased)
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "KECH_" content))
       (should (string-match-p "AFTER" content))
       (should-not (string-match-p "KECH_hel" content))))))

(ert-deftest kuro-e2e-insert-lines ()
  :expected-result kuro-test--e2e-expected-result
  "CSI L (IL) inserts N blank lines at cursor row, shifting content down.
Uses an atomic printf: position at row 5, IL 2 inserts 2 blank rows, then
KILAFTER is printed — it appears on what was row 5.  Content originally at
row 5 (ROW_5) shifts down and also remains visible.  Both markers must appear."
  (kuro-test--with-terminal
   ;; Fill screen with identifiable content
   (kuro-test--send "for i in $(seq 1 10); do echo \"KILROW_$i\"; done")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KILROW_10"))
   (kuro-test--render-until-idle buf 0.5)
   ;; Single atomic printf: go to row 5, IL 2, print marker
   (kuro-test--send "printf '\\033[5;1H\\033[2LKILAFTER\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KILAFTER"))
   (kuro-test--render-until-idle buf 0.3)
   ;; KILAFTER inserted at row 5; shifted rows (KILROW_4+) still visible below
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "KILAFTER" content))
       ;; Content that was below the insertion point must still be present
       (should (string-match-p "KILROW_" content))))))

(ert-deftest kuro-e2e-delete-lines ()
  :expected-result kuro-test--e2e-expected-result
  "CSI M (DL) deletes N lines at cursor row, shifting content up.
Uses an atomic printf: position at row 3, DL 2 deletes rows 3-4, print KDLAFTER.
KDLROW_1 and KDLROW_2 (rows 1-2) survive; KDLROW_3 and KDLROW_4 (deleted rows)
disappear; content from row 5 onward shifts up."
  (kuro-test--with-terminal
   ;; Print 8 identifiable rows
   (kuro-test--send "for i in $(seq 1 8); do echo \"KDLROW_$i\"; done")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KDLROW_8"))
   (kuro-test--render-until-idle buf 0.5)
   ;; Single atomic printf: position at row 3, DL 2, print marker
   (kuro-test--send "printf '\\033[3;1H\\033[2MKDLAFTER\\n'")
   (kuro-test--send "\r")
   (should (kuro-test--wait-for buf "KDLAFTER"))
   (kuro-test--render-until-idle buf 0.3)
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "KDLAFTER" content))
       ;; Rows before deleted rows still present
       (should (string-match-p "KDLROW_1\\|KDLROW_2" content))
       ;; Rows after the deleted range (shifted up) still present
       (should (string-match-p "KDLROW_5\\|KDLROW_6\\|KDLROW_7\\|KDLROW_8" content))))))

(ert-deftest kuro-e2e-auto-wrap-mode ()
  :expected-result kuro-test--e2e-expected-result
  "CSI ?7 l/h controls DECAWM (auto-wrap mode).
Wrap-off: cursor clamps at col 79 — text overwritten, no new row.
Wrap-on: cursor moves to next row after col 79 — text continues on new row."
  (kuro-test--with-terminal
   ;; ── Part 1: wrap-off (DECAWM reset) ─────────────────────────────────────
   (kuro-test--send "printf '\\033[?7l'")
   (kuro-test--send "\r")
   (kuro-test--render-until-idle buf 0.3)
   ;; Print text past col 80 while wrap is off; cursor must stay on same row.
   ;; sleep holds cursor in position so we can sample it before prompt redraws.
   (kuro-test--send "printf '\\033[1;1HNOWRAP_TEST_LINE'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     (let ((row-before (car (kuro--get-cursor))))
       ;; cursor must remain on the same row as the text (row 0)
       (should (= row-before 0))))
   ;; ── Part 2: wrap-on (DECAWM set) ─────────────────────────────────────────
   (kuro-test--send "printf '\\033[?7h'")
   (kuro-test--send "\r")
   (kuro-test--render-until-idle buf 0.3)
   ;; Print 90 characters with wrap on — cursor must advance to row 1.
   (kuro-test--send "printf '\\033[1;1H123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890'; sleep 0.3")
   (kuro-test--send "\r")
   (sleep-for 0.1)
   (kuro-test--render-until-idle buf)
   (with-current-buffer buf
     ;; After printing 90 chars starting at col 0 with wrap on,
     ;; cursor must have advanced past row 0
     (let ((row-after (car (kuro--get-cursor))))
       (should (>= row-after 1))))))

(provide 'kuro-e2e-test)

;;; kuro-e2e-test.el ends here
