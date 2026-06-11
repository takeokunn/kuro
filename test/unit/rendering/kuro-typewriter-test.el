;;; kuro-typewriter-test.el --- Unit tests for kuro-typewriter.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-typewriter.el (typewriter animation effect).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Helpers:
;;   - kuro-typewriter-test--with-buffer: temp buffer with typewriter state bound
;;   - kuro-typewriter-test--with-timer-stub: stubs run-with-timer, captures args
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

(ert-deftest kuro-typewriter-tick-writes-one-character ()
  "kuro--typewriter-tick advances written-len by 1 and writes the substring."
  (kuro-typewriter-test--with-buffer
    (insert "hello\n")
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "hello"
          kuro--typewriter-current-text-len 5
          kuro--typewriter-written-len 2)
    (let ((written-args nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (row text) (push (cons row text) written-args))))
        (kuro--typewriter-tick)
        ;; written-len was 2, so next-len = 3, substring = "hel"
        (should (= kuro--typewriter-written-len 3))
        (should (= (length written-args) 1))
        (should (equal (car written-args) '(0 . "hel")))))))

(ert-deftest kuro-typewriter-tick-writes-from-beginning ()
  "kuro--typewriter-tick with written-len=0 writes the first character."
  (kuro-typewriter-test--with-buffer
    (insert "abc\n")
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "abc"
          kuro--typewriter-current-text-len 3
          kuro--typewriter-written-len 0)
    (let ((written-args nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (row text) (push (cons row text) written-args))))
        (kuro--typewriter-tick)
        (should (= kuro--typewriter-written-len 1))
        (should (equal (car written-args) '(0 . "a")))))))

;;; Group 2: kuro--typewriter-tick — completion

(ert-deftest kuro-typewriter-tick-does-not-advance-when-complete ()
  "kuro--typewriter-tick is a no-op (resets state) when written-len equals text length."
  (kuro-typewriter-test--with-buffer
    (insert "hi\n")
    ;; written-len already equals length of text: row is fully written
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "hi"
          kuro--typewriter-written-len 2
          kuro--typewriter-queue nil)
    (let ((write-called nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row _text) (setq write-called t))))
        (kuro--typewriter-tick)
        ;; No write should happen; state should be reset since queue is empty
        (should-not write-called)
        (should-not kuro--typewriter-current-row)
        (should-not kuro--typewriter-current-text)
        (should (= kuro--typewriter-written-len 0))))))

(ert-deftest kuro-typewriter-tick-advances-to-next-queued-item-on-completion ()
  "When current row is fully written, tick dequeues the next item."
  (kuro-typewriter-test--with-buffer
    (insert "ab\ncd\n")
    ;; Row 0 fully written; row 1 queued
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "ab"
          kuro--typewriter-written-len 2
          kuro--typewriter-queue (list (cons 1 "cd")))
    (let ((write-called nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row _text) (setq write-called t))))
        (kuro--typewriter-tick)
        ;; Should have dequeued row 1 without writing yet (queue-next sets state)
        (should-not write-called)
        (should (= kuro--typewriter-current-row 1))
        (should (equal kuro--typewriter-current-text "cd"))
        (should (= kuro--typewriter-written-len 0))
        (should (null kuro--typewriter-queue))))))

;;; Group 3: kuro--typewriter-tick — empty queue

(ert-deftest kuro-typewriter-tick-noop-when-no-current-and-empty-queue ()
  "kuro--typewriter-tick is a no-op when there is no current row and queue is empty."
  (kuro-typewriter-test--with-buffer
    (setq kuro--typewriter-current-row nil
          kuro--typewriter-current-text nil
          kuro--typewriter-written-len 0
          kuro--typewriter-queue nil)
    (let ((write-called nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row _text) (setq write-called t))))
        (kuro--typewriter-tick)
        (should-not write-called)))))

(ert-deftest kuro-typewriter-tick-blocked-when-not-initialized ()
  "kuro--typewriter-tick does nothing when kuro--initialized is nil."
  (kuro-typewriter-test--with-buffer
    (setq kuro--initialized nil
          kuro--typewriter-current-row 0
          kuro--typewriter-current-text "text"
          kuro--typewriter-written-len 0)
    (let ((write-called nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row _text) (setq write-called t))))
        (kuro--typewriter-tick)
        (should-not write-called)
        ;; written-len must not have advanced
        (should (= kuro--typewriter-written-len 0))))))

;;; Group 4: kuro--typewriter-tick — single character text

(ert-deftest kuro-typewriter-tick-single-character-text ()
  "A single-character text is written in one tick and leaves written-len = 1."
  (kuro-typewriter-test--with-buffer
    (insert "x\n")
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "x"
          kuro--typewriter-current-text-len 1
          kuro--typewriter-written-len 0)
    (let ((written-args nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (row text) (push (cons row text) written-args))))
        (kuro--typewriter-tick)
        (should (= kuro--typewriter-written-len 1))
        (should (equal (car written-args) '(0 . "x")))))))

;;; Group N: kuro--typewriter-tick edge cases

(ert-deftest kuro-typewriter-tick-partial-write-mid-row ()
  "kuro--typewriter-tick writes exactly one character when mid-row (partial text).
A row whose written-len is already positive advances by exactly 1 per tick."
  (kuro-typewriter-test--with-buffer
    (insert "hello\n")
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "hello"
          kuro--typewriter-current-text-len 5
          kuro--typewriter-written-len 3)
    (let ((write-count 0)
          (last-written nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (_row text)
                   (cl-incf write-count)
                   (setq last-written text))))
        (kuro--typewriter-tick)
        ;; Must have written exactly once, advancing len by 1 (3 -> 4)
        (should (= write-count 1))
        (should (= kuro--typewriter-written-len 4))
        (should (equal last-written "hell"))))))

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
    (let ((write-calls nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (row text) (push (cons row text) write-calls))))
        ;; Tick 1: row 0 complete — should dequeue row 1, no write yet
        (kuro--typewriter-tick)
        (should (null write-calls))
        (should (= kuro--typewriter-current-row 1))
        (should (equal kuro--typewriter-current-text "cd"))
        (should (= kuro--typewriter-written-len 0))
        (should (null kuro--typewriter-queue))
        ;; Tick 2: row 1 in progress — should write first char "c"
        (kuro--typewriter-tick)
        (should (= (length write-calls) 1))
        (should (equal (car write-calls) '(1 . "c")))
        (should (= kuro--typewriter-written-len 1))))))

(ert-deftest kuro-typewriter-tick-resets-state-when-queue-empty ()
  "kuro--typewriter-tick resets all state vars when queue is empty after completion.
When written-len equals text length and the queue is empty, the `t' branch
fires: current-row, current-text become nil and written-len returns to 0."
  (kuro-typewriter-test--with-buffer
    (insert "xy\n")
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "xy"
          kuro--typewriter-written-len 2    ; fully written
          kuro--typewriter-queue nil)
    (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
               (lambda (_row _text) (error "write-partial must not be called"))))
      (kuro--typewriter-tick)
      (should (null kuro--typewriter-current-row))
      (should (null kuro--typewriter-current-text))
      (should (= kuro--typewriter-written-len 0)))))

(ert-deftest kuro-typewriter-tick-noop-when-not-initialized ()
  "kuro--typewriter-tick is a no-op when kuro--initialized is nil.
State variables remain unchanged; write-partial is never called."
  (kuro-typewriter-test--with-buffer
    (setq kuro--initialized nil
          kuro--typewriter-current-row 2
          kuro--typewriter-current-text "test"
          kuro--typewriter-written-len 1)
    (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
               (lambda (_row _text) (error "write-partial must not be called"))))
      (kuro--typewriter-tick)
      ;; State must be completely unchanged
      (should (= kuro--typewriter-current-row 2))
      (should (equal kuro--typewriter-current-text "test"))
      (should (= kuro--typewriter-written-len 1)))))

;;; Group N+1: kuro--typewriter-tick — additional edge cases

(ert-deftest kuro-typewriter-tick-empty-string-text-resets-state ()
  "kuro--typewriter-tick resets state immediately when current-text is empty string.
An empty text means written-len (0) is never < (length \"\") (0), so the first
cond branch is false; queue-next also returns nil (empty queue); the `t' branch
fires and resets all state."
  (kuro-typewriter-test--with-buffer
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text ""
          kuro--typewriter-written-len 0
          kuro--typewriter-queue nil)
    (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
               (lambda (_row _text) (error "write-partial must not be called on empty text"))))
      (kuro--typewriter-tick)
      (should (null kuro--typewriter-current-row))
      (should (null kuro--typewriter-current-text))
      (should (= kuro--typewriter-written-len 0)))))

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
    (let ((write-calls nil))
      (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                 (lambda (row text) (push (cons row text) write-calls))))
        ;; Tick 1: writes "a"
        (kuro--typewriter-tick)
        (should (= kuro--typewriter-written-len 1))
        ;; Tick 2: writes "ab"
        (kuro--typewriter-tick)
        (should (= kuro--typewriter-written-len 2))
        ;; Tick 3: writes "abc" — row now complete
        (kuro--typewriter-tick)
        (should (= kuro--typewriter-written-len 3))
        ;; write-partial called exactly 3 times, in order
        (should (= (length write-calls) 3))
        (should (equal (nth 2 write-calls) '(0 . "a")))
        (should (equal (nth 1 write-calls) '(0 . "ab")))
        (should (equal (nth 0 write-calls) '(0 . "abc")))
        ;; Tick 4: row complete, queue empty → state reset
        (kuro--typewriter-tick)
        (should (null kuro--typewriter-current-row))
        (should (null kuro--typewriter-current-text))
        (should (= kuro--typewriter-written-len 0))))))

(ert-deftest kuro-typewriter-tick-nil-text-falls-through-to-queue-next ()
  "kuro--typewriter-tick with current-row set but current-text nil falls through.
The first cond branch requires both row and text to be non-nil; if text is nil
the branch is skipped, queue-next is tried, and if queue is also empty state
resets to nil/nil/0."
  (kuro-typewriter-test--with-buffer
    ;; Simulate asymmetric state: row is set but text is nil
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text nil
          kuro--typewriter-written-len 0
          kuro--typewriter-queue nil)
    (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
               (lambda (_row _text) (error "write-partial must not be called"))))
      (kuro--typewriter-tick)
      ;; queue-next returned nil (empty queue) → t branch reset state
      (should (null kuro--typewriter-current-row))
      (should (null kuro--typewriter-current-text))
      (should (= kuro--typewriter-written-len 0)))))


(provide 'kuro-typewriter-test)
;;; kuro-typewriter-test.el ends here
