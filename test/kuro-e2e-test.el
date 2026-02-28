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

;;; Tests

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
       (should found-colored)))))

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
   ;; Buffer should not have consecutive blank lines (double-\n bug)
   (with-current-buffer buf
     (should-not (string-match-p "\n\n\n" (buffer-string))))))

(provide 'kuro-e2e-test)

;;; kuro-e2e-test.el ends here
