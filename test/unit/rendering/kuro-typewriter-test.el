;;; kuro-typewriter-test.el --- Unit tests for kuro-typewriter.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-typewriter.el (typewriter animation effect).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Helpers:
;;   - kuro-typewriter-test--with-buffer: temp buffer with typewriter state bound
;;   - kuro-typewriter-test--with-timer-stub: stubs run-with-timer, captures delay/repeat/fn
;;
;; Covered:
;;   - kuro--typewriter-tick: basic character advancement
;;   - kuro--typewriter-tick: empty queue / nothing to write
;;   - kuro--typewriter-tick: completion when written-len equals text length
;;   - kuro--typewriter-tick: single-character text written in one tick
;;   - kuro--typewriter-tick: partial write mid-row (advances exactly 1 char)
;;   - kuro--typewriter-tick: advances to next row after current row complete
;;   - kuro--typewriter-tick: resets all state when queue empty after completion
;;   - kuro--typewriter-tick: no-op when kuro--initialized is nil
;;   - kuro--typewriter-enqueue: items are queued correctly
;;   - kuro--typewriter-queue-next: pops from queue and resets state
;;   - kuro--typewriter-write-partial: writes substring to buffer row
;;   - kuro--start-typewriter-timer / kuro--stop-typewriter-timer: lifecycle

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-typewriter-test-support)

;;; Group 1: kuro--typewriter-tick — basic advancement

(kuro-typewriter-test--deftest-tick-partial-write-cases)

;;; Group 2: kuro--typewriter-tick — completion

(ert-deftest kuro-typewriter-tick-advances-to-next-queued-item-on-completion ()
  "When current row is fully written, tick dequeues the next item."
  (kuro-typewriter-test--with-buffer
    (insert "ab\ncd\n")
    ;; Row 0 fully written; row 1 queued
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "ab"
          kuro--typewriter-written-len 2
          kuro--typewriter-queue (list (cons 1 "cd")))
    (kuro-typewriter-test--with-write-partial-log write-calls
      (kuro--typewriter-tick)
      ;; queue-next sets state without writing on the completion tick
      (should-not write-calls)
      (kuro-typewriter-test--assert-state 1 "cd" 0 nil))))

;;; Group 3: kuro--typewriter-tick — empty queue

(kuro-typewriter-test--deftest-tick-no-write-state-cases)

;;; Group 4: kuro--typewriter-tick — queued row transition

(ert-deftest kuro-typewriter-tick-advances-to-next-row-at-end ()
  "kuro--typewriter-tick dequeues the next row when the current row is fully written.
On the tick where written-len equals text length, queue-next fires; the
following tick then starts writing the new row."
  (kuro-typewriter-test--with-buffer
    (insert "ab\ncd\n")
    ;; Row 0 fully written (len == text length)
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "ab"
          kuro--typewriter-written-len 2
          kuro--typewriter-queue (list (cons 1 "cd")))
    (kuro-typewriter-test--with-write-partial-log write-calls
      (kuro-typewriter-test--tick-sequence
        (tick
         (should (null write-calls))
         (kuro-typewriter-test--assert-state 1 "cd" 0 nil))
        (tick
         (should (= (length write-calls) 1))
         (should (equal (car write-calls) '(1 . "c")))
         (kuro-typewriter-test--assert-state 1 "cd" 1 nil))))))

;;; Group 5: kuro--typewriter-tick — multi-tick row drain

(ert-deftest kuro-typewriter-tick-drains-full-row-char-by-char ()
  "kuro--typewriter-tick drains a 3-character row in exactly 3 ticks.
Each tick advances written-len by 1; after 3 ticks the row is complete and
the next tick (with empty queue) resets state."
  (kuro-typewriter-test--with-buffer
    (insert "abc\n")
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "abc"
          kuro--typewriter-current-text-len 3
          kuro--typewriter-written-len 0
          kuro--typewriter-queue nil)
    (kuro-typewriter-test--with-write-partial-log write-calls
      (kuro-typewriter-test--tick-sequence
        (tick
         (should (= kuro--typewriter-written-len 1)))
        (tick
         (should (= kuro--typewriter-written-len 2)))
        (tick
         (should (= kuro--typewriter-written-len 3))
         (should (= (length write-calls) 3))
         (should (equal (nth 2 write-calls) '(0 . "a")))
         (should (equal (nth 1 write-calls) '(0 . "ab")))
         (should (equal (nth 0 write-calls) '(0 . "abc"))))
        (tick
         (kuro-typewriter-test--assert-state nil nil 0 nil))))))

(provide 'kuro-typewriter-test)
;;; kuro-typewriter-test.el ends here
