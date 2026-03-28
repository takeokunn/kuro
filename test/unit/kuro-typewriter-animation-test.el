;;; kuro-typewriter-ext-test.el --- Extended unit tests for kuro-typewriter.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for kuro-typewriter.el (typewriter animation effect).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Helpers:
;;   - kuro-typewriter-test--with-buffer: temp buffer with typewriter state bound
;;   - kuro-typewriter-test--with-timer-stub: stubs run-with-timer, captures args
;;   - kuro-typewriter-test--with-key-capture: stubs kuro--send-key, captures output
;;
;; Covered (Groups 10-16):
;;   - kuro--typewriter-write-partial: buffer content correctness (Group 10)
;;   - kuro--typewriter-tick: Unicode and long string edge cases (Group 11)
;;   - typewriter + streaming interaction (Group 12)
;;   - kuro--typewriter-queue-next: written-len reset + remaining edge cases (Group 13)
;;   - kuro--typewriter-write-partial: buffer boundary and empty-buffer edge cases (Group 14)
;;   - kuro--start-typewriter-timer: closure and buffer capture (Group 15)
;;   - special key byte sequences: RET, TAB, DEL, Ctrl codes (Group 16)

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-typewriter)

;;; Helpers

(defmacro kuro-typewriter-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with typewriter state initialized.
`kuro--initialized' is set to t so that `kuro--typewriter-tick' guards pass."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized t)
           kuro--typewriter-queue
           kuro--typewriter-timer
           kuro--typewriter-current-row
           kuro--typewriter-current-text
           (kuro--typewriter-written-len 0))
       ,@body)))

(defmacro kuro-typewriter-test--with-timer-stub (var &rest body)
  "Run BODY with `run-with-timer' stubbed; VAR captures the created timer.
The stub stores (DELAY FN) as a list in VAR and returns the symbol
`fake-timer'.  Use this when tests need to verify timer creation
arguments without actually scheduling real timers."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'run-with-timer)
                (lambda (delay _repeat fn)
                  (setq ,var (list delay fn))
                  'fake-timer)))
       ,@body)))

(defmacro kuro-typewriter-test--with-key-capture (var &rest body)
  "Run BODY with `kuro--send-key' captured into VAR (most recent first).
`kuro--schedule-immediate-render' is stubbed as a no-op."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (push data ,var)))
               ((symbol-function 'kuro--schedule-immediate-render)
                (lambda () nil)))
       ,@body)))

;;; Group 10: kuro--typewriter-write-partial — buffer content correctness

(ert-deftest kuro-typewriter-write-partial-empty-string-clears-line ()
  "kuro--typewriter-write-partial with empty string deletes the line content."
  (kuro-typewriter-test--with-buffer
    (insert "original text\n")
    (kuro--typewriter-write-partial 0 "")
    (goto-char (point-min))
    ;; Line content must be empty (just the newline remains)
    (should (= (line-end-position) (line-beginning-position)))))

(ert-deftest kuro-typewriter-write-partial-unicode-text ()
  "kuro--typewriter-write-partial correctly writes a Unicode multi-byte string."
  (kuro-typewriter-test--with-buffer
    (insert "placeholder\n")
    (kuro--typewriter-write-partial 0 "日本語")
    (goto-char (point-min))
    (should (looking-at "日本語\n"))))

(ert-deftest kuro-typewriter-write-partial-second-row-unicode ()
  "kuro--typewriter-write-partial writes Unicode to a non-zero row."
  (kuro-typewriter-test--with-buffer
    (insert "row0\nplaceholder\n")
    (kuro--typewriter-write-partial 1 "αβγ")
    (goto-char (point-min))
    (forward-line 1)
    (should (looking-at "αβγ\n"))))

;;; Group 11: kuro--typewriter-tick — Unicode and long string edge cases

(ert-deftest kuro-typewriter-tick-unicode-text-advances-by-one-char ()
  "kuro--typewriter-tick with multi-byte Unicode text advances written-len by 1.
Elisp `length' counts characters (not bytes), so a 3-char CJK string has
length 3; after one tick written-len goes from 0 to 1, substring = first char."
  (kuro-typewriter-test--with-buffer
    (insert "日本語\n")
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "日本語"
          kuro--typewriter-written-len 0)
    (let ((last-written nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row text) (setq last-written text))))
        (kuro--typewriter-tick)
        (should (= kuro--typewriter-written-len 1))
        (should (equal last-written "日"))))))

(ert-deftest kuro-typewriter-tick-long-string-char-by-char ()
  "kuro--typewriter-tick handles a 10-character string; each tick advances by 1."
  (kuro-typewriter-test--with-buffer
    (let ((text "0123456789")
          (tick-count 0))
      (insert (concat text "\n"))
      (setq kuro--typewriter-current-row 0
            kuro--typewriter-current-text text
            kuro--typewriter-written-len 0)
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row _text) (cl-incf tick-count))))
        ;; 10 ticks to fully write the row
        (dotimes (_ 10)
          (kuro--typewriter-tick))
        (should (= tick-count 10))
        (should (= kuro--typewriter-written-len 10))))))

;;; Group 12: typewriter + streaming interaction (pure state logic)

(ert-deftest kuro-typewriter-enqueue-then-tick-renders-correct-partial ()
  "Enqueue a row, then tick twice: first tick starts writing, second advances."
  (kuro-typewriter-test--with-buffer
    (insert "hi\n")
    ;; Enqueue item directly
    (kuro--typewriter-enqueue 0 "hi")
    ;; queue-next must dequeue on first tick (no current row set)
    (let ((written-texts nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row text) (push text written-texts))))
        ;; Tick 1: queue-next dequeues, no write yet
        (kuro--typewriter-tick)
        (should (null written-texts))
        (should (equal kuro--typewriter-current-text "hi"))
        ;; Tick 2: writes first character "h"
        (kuro--typewriter-tick)
        (should (equal (car written-texts) "h"))
        (should (= kuro--typewriter-written-len 1))))))

(ert-deftest kuro-typewriter-enqueue-multiple-then-drain-two-rows ()
  "Enqueue two rows and verify that draining sets up both correctly in order."
  (kuro-typewriter-test--with-buffer
    ;; push inserts at head so we push second then first to get LIFO drain
    (kuro--typewriter-enqueue 0 "row-a")
    (kuro--typewriter-enqueue 1 "row-b")
    ;; Queue is now: ((1 . "row-b") (0 . "row-a")) due to push
    (should (= (length kuro--typewriter-queue) 2))
    ;; First queue-next pops the head: row 1 "row-b"
    (kuro--typewriter-queue-next)
    (should (= kuro--typewriter-current-row 1))
    (should (equal kuro--typewriter-current-text "row-b"))
    (should (= (length kuro--typewriter-queue) 1))
    ;; Second queue-next pops: row 0 "row-a"
    (kuro--typewriter-queue-next)
    (should (= kuro--typewriter-current-row 0))
    (should (equal kuro--typewriter-current-text "row-a"))
    (should (null kuro--typewriter-queue))))

(ert-deftest kuro-typewriter-effect-disabled-start-timer-leaves-timer-nil ()
  "When kuro-typewriter-effect is nil, timer remains nil even after start is called.
This verifies that enabling streaming while typewriter is off does not leak timers."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect nil))
      (kuro--start-typewriter-timer)
      (should (null kuro--typewriter-timer)))))

(ert-deftest kuro-typewriter-write-partial-row-zero-multiple-calls ()
  "kuro--typewriter-write-partial can be called multiple times on the same row.
Each call fully replaces the row content with the new text."
  (kuro-typewriter-test--with-buffer
    (insert "initial\n")
    (kuro--typewriter-write-partial 0 "first")
    (goto-char (point-min))
    (should (looking-at "first\n"))
    (kuro--typewriter-write-partial 0 "second")
    (goto-char (point-min))
    (should (looking-at "second\n"))))

;;; Group 13: kuro--typewriter-queue-next — written-len reset and remaining edge cases

(ert-deftest kuro-typewriter-queue-next-resets-written-len-from-nonzero ()
  "kuro--typewriter-queue-next resets kuro--typewriter-written-len to 0
even when it was previously non-zero (e.g., from a prior partially-written row)."
  (kuro-typewriter-test--with-buffer
    (setq kuro--typewriter-queue (list (cons 4 "new"))
          kuro--typewriter-written-len 7)   ; simulate leftover state
    (kuro--typewriter-queue-next)
    (should (= kuro--typewriter-written-len 0))
    (should (= kuro--typewriter-current-row 4))
    (should (equal kuro--typewriter-current-text "new"))))

(ert-deftest kuro-typewriter-queue-next-returns-t-on-non-empty-queue ()
  "kuro--typewriter-queue-next returns exactly t (non-nil) when an item is dequeued."
  (kuro-typewriter-test--with-buffer
    (setq kuro--typewriter-queue (list (cons 0 "x")))
    (should (eq t (kuro--typewriter-queue-next)))))

(ert-deftest kuro-typewriter-write-partial-buffer-without-trailing-newline ()
  "kuro--typewriter-write-partial works on row 0 even when the buffer has no
trailing newline — forward-line 0 is a no-op, point stays at bol."
  (kuro-typewriter-test--with-buffer
    ;; Insert a line without a trailing newline
    (insert "no-newline")
    (kuro--typewriter-write-partial 0 "replaced")
    (goto-char (point-min))
    (should (looking-at "replaced"))))

(ert-deftest kuro-typewriter-start-timer-repeat-equals-delay ()
  "kuro--start-typewriter-timer passes the same value for both DELAY and REPEAT
arguments to `run-with-timer', so the timer fires at a constant rate."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 30)
          (captured nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (delay repeat fn)
                   (setq captured (list delay repeat fn))
                   'fake-timer)))
        (kuro--start-typewriter-timer)
        (should captured)
        (let ((delay  (nth 0 captured))
              (repeat (nth 1 captured)))
          ;; Both must be equal and = 1.0/30
          (should (floatp delay))
          (should (floatp repeat))
          (should (< (abs (- delay repeat)) 1e-10))
          (should (< (abs (- delay (/ 1.0 30))) 1e-10)))))))

(ert-deftest kuro-typewriter-start-timer-callback-is-function ()
  "kuro--start-typewriter-timer passes a callable function as the timer callback."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 60)
          (captured-fn nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (_delay _repeat fn)
                   (setq captured-fn fn)
                   'fake-timer)))
        (kuro--start-typewriter-timer)
        (should (functionp captured-fn))))))

;;; Group 14 — kuro--typewriter-write-partial: buffer boundary and empty-buffer edge cases

(ert-deftest kuro-typewriter-write-partial-empty-buffer-row0-is-noop ()
  "kuro--typewriter-write-partial on row 0 of a completely empty buffer.
forward-line 0 on an empty buffer is a no-op (returns 0); point stays at
bol of line 0, so delete-region and insert execute on the empty line."
  (kuro-typewriter-test--with-buffer
    ;; Completely empty buffer — no content, no newline
    (should-not
     (condition-case err
         (progn (kuro--typewriter-write-partial 0 "x") nil)
       (error err)))
    (goto-char (point-min))
    (should (looking-at "x"))))

(ert-deftest kuro-typewriter-write-partial-row1-when-only-one-line-is-noop ()
  "kuro--typewriter-write-partial on row 1 when buffer has only one line.
forward-line 1 from point-min moves past EOF; not-moved is non-zero, so
the write is skipped and the buffer content is unchanged."
  (kuro-typewriter-test--with-buffer
    (insert "only\n")
    (kuro--typewriter-write-partial 1 "should-not-appear")
    (goto-char (point-min))
    ;; Buffer must still contain only the original line
    (should (looking-at "only\n"))
    (should (= (line-number-at-pos (point-max)) 2))))

(ert-deftest kuro-typewriter-write-partial-last-line-no-newline ()
  "kuro--typewriter-write-partial on the last line of a buffer without a trailing newline.
forward-line N lands on the last line (returns 0); delete-region then insert work normally."
  (kuro-typewriter-test--with-buffer
    (insert "line0\nline1\nlast")   ; no trailing newline
    (kuro--typewriter-write-partial 2 "replaced")
    (goto-char (point-min))
    (forward-line 2)
    (should (looking-at "replaced"))))

(ert-deftest kuro-typewriter-write-partial-does-not-move-point ()
  "kuro--typewriter-write-partial uses save-excursion: point is unchanged after the call."
  (kuro-typewriter-test--with-buffer
    (insert "row0\nrow1\n")
    (goto-char (point-max))
    (let ((saved-point (point)))
      (kuro--typewriter-write-partial 0 "new0")
      (should (= (point) saved-point)))))

(ert-deftest kuro-typewriter-write-partial-wide-unicode-replaces-line ()
  "kuro--typewriter-write-partial correctly replaces a line with wide Unicode characters."
  (kuro-typewriter-test--with-buffer
    (insert "narrow\n")
    ;; CJK wide characters: each renders as 2 columns
    (kuro--typewriter-write-partial 0 "全角文字")
    (goto-char (point-min))
    (should (looking-at "全角文字\n"))))

;;; Group 15 — kuro--start-typewriter-timer: closure and buffer capture

(ert-deftest kuro-typewriter-start-timer-callback-is-closure-over-buffer ()
  "The timer callback created by kuro--start-typewriter-timer captures the
current buffer and switches to it before calling kuro--typewriter-tick.
Verify that the lambda closed over `buf' is the buffer in which start was called."
  (kuro-typewriter-test--with-buffer
    (let* ((kuro-typewriter-effect t)
           (kuro-typewriter-chars-per-second 60)
           (captured-fn nil)
           (outer-buf (current-buffer)))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (_delay _repeat fn)
                   (setq captured-fn fn)
                   'fake-timer)))
        (kuro--start-typewriter-timer)
        (should (functionp captured-fn))
        ;; Invoke the callback in a different temp buffer; it should
        ;; execute kuro--typewriter-tick in outer-buf (which is live).
        (let ((tick-buf nil))
          (cl-letf (((symbol-function 'kuro--typewriter-tick)
                     (lambda () (setq tick-buf (current-buffer)))))
            (funcall captured-fn)
            ;; The closure should have switched to outer-buf
            (should (eq tick-buf outer-buf))))))))

(ert-deftest kuro-typewriter-start-timer-callback-skips-dead-buffer ()
  "The timer callback is a no-op when the captured buffer is dead.
If the buffer is killed between timer creation and the tick, the
`buffer-live-p' guard must prevent kuro--typewriter-tick from being called."
  (let ((captured-fn nil)
        (tick-called nil))
    (let ((buf (generate-new-buffer "*kuro-tw-dead-test*")))
      (unwind-protect
          (with-current-buffer buf
            (let ((kuro-typewriter-effect t)
                  (kuro-typewriter-chars-per-second 60)
                  (kuro--initialized t)
                  kuro--typewriter-queue
                  kuro--typewriter-timer
                  kuro--typewriter-current-row
                  kuro--typewriter-current-text
                  (kuro--typewriter-written-len 0))
              (cl-letf (((symbol-function 'run-with-timer)
                         (lambda (_delay _repeat fn)
                           (setq captured-fn fn)
                           'fake-timer)))
                (kuro--start-typewriter-timer))))
        ;; Kill the buffer before firing the callback
        (kill-buffer buf)))
    ;; Now fire the callback — buffer is dead
    (cl-letf (((symbol-function 'kuro--typewriter-tick)
               (lambda () (setq tick-called t))))
      (when captured-fn (funcall captured-fn)))
    (should-not tick-called)))

(ert-deftest kuro-typewriter-start-timer-one-cps-interval-is-one-second ()
  "At 1 CPS, interval = 1.0/max(1,1) = 1.0 exactly."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 1)
          (captured-delay nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (delay _repeat _fn)
                   (setq captured-delay delay)
                   'fake-timer)))
        (kuro--start-typewriter-timer)
        (should (floatp captured-delay))
        (should (< (abs (- captured-delay 1.0)) 1e-10))))))

(ert-deftest kuro-typewriter-enqueue-zero-row-empty-text ()
  "kuro--typewriter-enqueue correctly queues row 0 with an empty string."
  (kuro-typewriter-test--with-buffer
    (kuro--typewriter-enqueue 0 "")
    (should (= (length kuro--typewriter-queue) 1))
    (should (equal (car kuro--typewriter-queue) '(0 . "")))))

(ert-deftest kuro-typewriter-queue-next-empty-string-text-sets-state ()
  "kuro--typewriter-queue-next dequeues an empty-string text without error."
  (kuro-typewriter-test--with-buffer
    (setq kuro--typewriter-queue (list (cons 0 "")))
    (let ((result (kuro--typewriter-queue-next)))
      (should result)
      (should (= kuro--typewriter-current-row 0))
      (should (equal kuro--typewriter-current-text ""))
      (should (= kuro--typewriter-written-len 0)))))

;;; Group 16 — special key byte sequences (RET, TAB, DEL, Ctrl codes)

;; These tests verify the byte values that kuro--RET, kuro--TAB, kuro--DEL,
;; and kuro--send-special send to the PTY.  kuro--send-special is loaded as
;; a transitive dependency (kuro-typewriter -> kuro-renderer -> kuro-input).
;; We stub kuro--send-key and kuro--schedule-immediate-render to capture output.

(ert-deftest kuro-typewriter-ret-sends-carriage-return ()
  "kuro--RET sends the carriage-return byte \\x0d (ASCII 13)."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--RET)
    (should (equal (car sent) (string ?\r)))))

(ert-deftest kuro-typewriter-tab-sends-horizontal-tab ()
  "kuro--TAB sends the horizontal-tab byte \\x09 (ASCII 9)."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--TAB)
    (should (equal (car sent) (string ?\t)))))

(ert-deftest kuro-typewriter-del-sends-rubout-byte ()
  "kuro--DEL sends the DEL byte \\x7f (ASCII 127), the modern backspace."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--DEL)
    (should (equal (car sent) (string ?\x7f)))))

(ert-deftest kuro-typewriter-send-special-ctrl-a ()
  "kuro--send-special 1 sends \\x01 (Ctrl+A / SOH)."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--send-special 1)
    (should (equal (car sent) (string 1)))))

(ert-deftest kuro-typewriter-send-special-ctrl-c ()
  "kuro--send-special 3 sends \\x03 (Ctrl+C / ETX)."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--send-special 3)
    (should (equal (car sent) (string 3)))))

(ert-deftest kuro-typewriter-send-special-ctrl-z ()
  "kuro--send-special 26 sends \\x1a (Ctrl+Z / SUB)."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--send-special 26)
    (should (equal (car sent) (string 26)))))

(ert-deftest kuro-typewriter-send-special-ctrl-bracket ()
  "kuro--send-special 27 sends \\x1b (ESC / Ctrl+[)."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--send-special 27)
    (should (equal (car sent) (string 27)))))

(ert-deftest kuro-typewriter-send-special-ctrl-backslash ()
  "kuro--send-special 28 sends \\x1c (Ctrl+\\\\)."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--send-special 28)
    (should (equal (car sent) (string 28)))))

(ert-deftest kuro-typewriter-send-special-ctrl-right-bracket ()
  "kuro--send-special 29 sends \\x1d (Ctrl+])."
  (kuro-typewriter-test--with-key-capture sent
    (kuro--send-special 29)
    (should (equal (car sent) (string 29)))))

(ert-deftest kuro-typewriter-send-special-sends-exactly-one-byte-string ()
  "kuro--send-special always sends a single-byte string to the PTY."
  (dolist (byte '(1 3 9 13 26 27 28 29 127))
    (kuro-typewriter-test--with-key-capture sent
      (kuro--send-special byte)
      (should (= (length sent) 1))
      (should (= (length (car sent)) 1)))))

;;; Group 17 — kuro--typewriter-tick: dead buffer after enqueue

(ert-deftest kuro-typewriter-ext-tick-handles-dead-buffer-after-enqueue ()
  "The timer closure is a no-op and signals no error when the buffer is dead.
Enqueue text, kill the buffer, then fire the captured timer lambda directly.
The `buffer-live-p' guard in the closure must prevent any error."
  (let ((captured-fn nil))
    (let ((buf (generate-new-buffer "*kuro-tw-dead-enqueue-test*")))
      (unwind-protect
          (with-current-buffer buf
            (let ((kuro-typewriter-effect t)
                  (kuro-typewriter-chars-per-second 60)
                  (kuro--initialized t)
                  kuro--typewriter-queue
                  kuro--typewriter-timer
                  kuro--typewriter-current-row
                  kuro--typewriter-current-text
                  (kuro--typewriter-written-len 0))
              (kuro--typewriter-enqueue 0 "hello")
              (cl-letf (((symbol-function 'run-with-timer)
                         (lambda (_delay _repeat fn)
                           (setq captured-fn fn)
                           'fake-timer)))
                (kuro--start-typewriter-timer))))
        (kill-buffer buf)))
    ;; Buffer is now dead; fire the closure — must not error
    (should-not
     (condition-case err
         (progn (when captured-fn (funcall captured-fn)) nil)
       (error err)))))

(ert-deftest kuro-typewriter-ext-tick-dead-buffer-does-not-render ()
  "kuro--typewriter-tick is never called when the captured buffer is dead.
After kill-buffer, the closure's buffer-live-p guard must suppress the tick."
  (let ((captured-fn nil)
        (tick-called nil))
    (let ((buf (generate-new-buffer "*kuro-tw-dead-render-test*")))
      (unwind-protect
          (with-current-buffer buf
            (let ((kuro-typewriter-effect t)
                  (kuro-typewriter-chars-per-second 60)
                  (kuro--initialized t)
                  kuro--typewriter-queue
                  kuro--typewriter-timer
                  kuro--typewriter-current-row
                  kuro--typewriter-current-text
                  (kuro--typewriter-written-len 0))
              (kuro--typewriter-enqueue 0 "hello")
              (cl-letf (((symbol-function 'run-with-timer)
                         (lambda (_delay _repeat fn)
                           (setq captured-fn fn)
                           'fake-timer)))
                (kuro--start-typewriter-timer))))
        (kill-buffer buf)))
    (cl-letf (((symbol-function 'kuro--typewriter-tick)
               (lambda () (setq tick-called t))))
      (when captured-fn (funcall captured-fn)))
    (should-not tick-called)))

(ert-deftest kuro-typewriter-ext-tick-state-cleared-after-dead-buffer ()
  "kuro--typewriter-tick resets state vars to nil/0 when queue is drained.
After the dead buffer closure is a no-op, the state clearing path is
exercised when tick is called directly on a fresh buffer with completed queue."
  ;; Simulate a state where a row was fully written and queue is empty —
  ;; the same reset path that fires after a dead-buffer scenario clears the queue.
  (with-temp-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (kuro--initialized t)
          (kuro--typewriter-current-row 0)
          (kuro--typewriter-current-text "hi")
          (kuro--typewriter-written-len 2)   ; fully written
          (kuro--typewriter-queue nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row _text) (error "must not write"))))
        (kuro--typewriter-tick)
        ;; After dead-queue reset path: current-row and current-text become nil
        (should (null kuro--typewriter-current-row))
        (should (null kuro--typewriter-current-text))
        (should (= kuro--typewriter-written-len 0))))))

(provide 'kuro-typewriter-ext-test)

;;; kuro-typewriter-ext-test.el ends here
