;;; kuro-typewriter-ext-test.el --- Typewriter tests: buffer content, streaming  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-typewriter.el — Groups 10-15.
;; Groups 1-9 are in kuro-typewriter-test.el.
;; Groups 16-17 are in kuro-typewriter-keys-test.el.
;; Helper macros are in kuro-typewriter-test-support.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-typewriter-test-support)

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
          kuro--typewriter-current-text-len 3
          kuro--typewriter-written-len 0)
    (kuro-typewriter-test--with-write-partial-log write-calls
      (kuro--typewriter-tick)
      (kuro-typewriter-test--assert-state 0 "日本語" 1 nil)
      (should (equal write-calls '((0 . "日")))))))

(ert-deftest kuro-typewriter-tick-long-string-char-by-char ()
  "kuro--typewriter-tick handles a 10-character string; each tick advances by 1."
  (kuro-typewriter-test--with-buffer
    (let ((text "0123456789"))
      (insert (concat text "\n"))
      (setq kuro--typewriter-current-row 0
            kuro--typewriter-current-text text
            kuro--typewriter-current-text-len (length text)
            kuro--typewriter-written-len 0)
      (kuro-typewriter-test--with-write-partial-log write-calls
        ;; 10 ticks to fully write the row
        (dotimes (_ 10)
          (kuro--typewriter-tick))
        (should (= (length write-calls) 10))
        (kuro-typewriter-test--assert-state 0 text 10 nil)))))

;;; Group 12: typewriter + streaming interaction (pure state logic)

(ert-deftest kuro-typewriter-enqueue-then-tick-renders-correct-partial ()
  "Enqueue a row, then tick twice: first tick starts writing, second advances."
  (kuro-typewriter-test--with-buffer
    (insert "hi\n")
    ;; Enqueue item directly
    (kuro--typewriter-enqueue 0 "hi")
    ;; queue-next must dequeue on first tick (no current row set)
    (kuro-typewriter-test--with-write-partial-log write-calls
      ;; Tick 1: queue-next dequeues, no write yet
      (kuro--typewriter-tick)
      (should (null write-calls))
      (kuro-typewriter-test--assert-state 0 "hi" 0 nil)
      ;; Tick 2: writes first character "h"
      (kuro--typewriter-tick)
      (should (equal write-calls '((0 . "h"))))
      (kuro-typewriter-test--assert-state 0 "hi" 1 nil))))

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
      (kuro-typewriter-test--with-timer-stub captured
        (kuro--start-typewriter-timer)
        (should captured)
        ;; Both must be equal and = 1.0/30
        (should (floatp (nth 0 captured)))
        (should (floatp (nth 1 captured)))
        (should (< (abs (- (nth 0 captured) (nth 1 captured))) 1e-10))
        (should (< (abs (- (nth 0 captured) (/ 1.0 30))) 1e-10))))))

(ert-deftest kuro-typewriter-start-timer-callback-is-function ()
  "kuro--start-typewriter-timer passes a callable function as the timer callback."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 60)
          (captured-fn nil))
      (kuro-typewriter-test--with-timer-stub captured
        (kuro--start-typewriter-timer)
        (setq captured-fn (nth 2 captured))
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
      (kuro-typewriter-test--with-timer-stub captured
        (kuro--start-typewriter-timer)
        (setq captured-fn (nth 2 captured))
        (should (functionp captured-fn))
        ;; Invoke the callback in a different temp buffer; it should
        ;; execute kuro--typewriter-tick in outer-buf (which is live).
        (let ((tick-buf nil))
          (cl-letf (((symbol-function 'kuro--typewriter-tick)
                     (lambda () (setq tick-buf (current-buffer)))))
            (funcall captured-fn)
            ;; The closure should have switched to outer-buf
            (should (eq tick-buf outer-buf))))))))


(ert-deftest kuro-typewriter-start-timer-one-cps-interval-is-one-second ()
  "At 1 CPS, interval = 1.0/max(1,1) = 1.0 exactly."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 1)
          (captured-delay nil))
      (kuro-typewriter-test--with-timer-stub captured
        (kuro--start-typewriter-timer)
        (setq captured-delay (nth 0 captured))
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

(provide 'kuro-typewriter-ext-test)

;;; kuro-typewriter-ext-test.el ends here
