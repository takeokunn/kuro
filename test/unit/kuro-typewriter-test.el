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

;;; Group 1: kuro--typewriter-tick — basic advancement

(ert-deftest kuro-typewriter-tick-writes-one-character ()
  "kuro--typewriter-tick advances written-len by 1 and writes the substring."
  (kuro-typewriter-test--with-buffer
    (insert "hello\n")
    (setq kuro--typewriter-current-row 0
          kuro--typewriter-current-text "hello"
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

;;; Group 5: kuro--typewriter-enqueue

(ert-deftest kuro-typewriter-enqueue-adds-to-queue ()
  "kuro--typewriter-enqueue pushes a (row . text) cons onto the queue."
  (kuro-typewriter-test--with-buffer
    (kuro--typewriter-enqueue 3 "hello")
    (should (= (length kuro--typewriter-queue) 1))
    (should (equal (car kuro--typewriter-queue) '(3 . "hello")))))

(ert-deftest kuro-typewriter-enqueue-multiple-items ()
  "kuro--typewriter-enqueue preserves all items when called multiple times."
  (kuro-typewriter-test--with-buffer
    (kuro--typewriter-enqueue 0 "first")
    (kuro--typewriter-enqueue 1 "second")
    (should (= (length kuro--typewriter-queue) 2))))

;;; Group 6: kuro--typewriter-queue-next

(ert-deftest kuro-typewriter-queue-next-returns-nil-on-empty-queue ()
  "kuro--typewriter-queue-next returns nil when the queue is empty."
  (kuro-typewriter-test--with-buffer
    (should-not (kuro--typewriter-queue-next))))

(ert-deftest kuro-typewriter-queue-next-pops-item-and-sets-state ()
  "kuro--typewriter-queue-next dequeues the last item and initializes state."
  (kuro-typewriter-test--with-buffer
    (setq kuro--typewriter-queue (list (cons 2 "world")))
    (let ((result (kuro--typewriter-queue-next)))
      (should result)
      (should (= kuro--typewriter-current-row 2))
      (should (equal kuro--typewriter-current-text "world"))
      (should (= kuro--typewriter-written-len 0))
      (should (null kuro--typewriter-queue)))))

(ert-deftest kuro-typewriter-queue-next-pops-car ()
  "kuro--typewriter-queue-next uses `pop', which takes the car (most-recently-pushed item)."
  (kuro-typewriter-test--with-buffer
    ;; List: ((5 . "second") (3 . "first")); pop returns car = (5 . "second")
    (setq kuro--typewriter-queue (list (cons 5 "second") (cons 3 "first")))
    (kuro--typewriter-queue-next)
    (should (= kuro--typewriter-current-row 5))
    (should (equal kuro--typewriter-current-text "second"))))

;;; Group 7: kuro--typewriter-write-partial

(ert-deftest kuro-typewriter-write-partial-replaces-line-content ()
  "kuro--typewriter-write-partial replaces the text on the target row."
  (kuro-typewriter-test--with-buffer
    (insert "original\nsecond\n")
    (kuro--typewriter-write-partial 0 "new")
    (goto-char (point-min))
    (should (looking-at "new\n"))))

(ert-deftest kuro-typewriter-write-partial-targets-correct-row ()
  "kuro--typewriter-write-partial writes to the specified row, not row 0."
  (kuro-typewriter-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (kuro--typewriter-write-partial 1 "updated")
    (goto-char (point-min))
    (forward-line 1)
    (should (looking-at "updated\n"))))

(ert-deftest kuro-typewriter-write-partial-preserves-other-rows ()
  "kuro--typewriter-write-partial leaves non-target rows unchanged."
  (kuro-typewriter-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (kuro--typewriter-write-partial 1 "X")
    (goto-char (point-min))
    (should (looking-at "row0\n"))
    (forward-line 2)
    (should (looking-at "row2\n"))))

(ert-deftest kuro-typewriter-write-partial-noop-on-out-of-bounds-row ()
  "kuro--typewriter-write-partial is a no-op when row exceeds buffer line count."
  (kuro-typewriter-test--with-buffer
    (insert "only-line\n")
    ;; Row 5 does not exist; should not error and buffer should be unchanged
    (should-not (condition-case err
                    (progn (kuro--typewriter-write-partial 5 "x") nil)
                  (error err)))
    (goto-char (point-min))
    (should (looking-at "only-line\n"))))

;;; Group 8: kuro--start-typewriter-timer / kuro--stop-typewriter-timer

(ert-deftest kuro-typewriter-start-timer-creates-timer-when-effect-enabled ()
  "kuro--start-typewriter-timer creates a timer when kuro-typewriter-effect is t."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 60))
      (kuro--start-typewriter-timer)
      (should (timerp kuro--typewriter-timer))
      (kuro--stop-typewriter-timer))))

(ert-deftest kuro-typewriter-start-timer-noop-when-effect-disabled ()
  "kuro--start-typewriter-timer does nothing when kuro-typewriter-effect is nil."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect nil))
      (kuro--start-typewriter-timer)
      (should-not kuro--typewriter-timer))))

(ert-deftest kuro-typewriter-stop-timer-cancels-timer ()
  "kuro--stop-typewriter-timer cancels the timer and sets it to nil."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 60))
      (kuro--start-typewriter-timer)
      (should (timerp kuro--typewriter-timer))
      (kuro--stop-typewriter-timer)
      (should-not kuro--typewriter-timer))))

(ert-deftest kuro-typewriter-stop-timer-idempotent ()
  "kuro--stop-typewriter-timer is safe to call when no timer is running."
  (kuro-typewriter-test--with-buffer
    (should-not (condition-case err
                    (progn (kuro--stop-typewriter-timer) nil)
                  (error err)))))

(ert-deftest kuro-typewriter-start-timer-replaces-existing-timer ()
  "kuro--start-typewriter-timer cancels any existing timer before creating a new one."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 60))
      (kuro--start-typewriter-timer)
      (let ((first-timer kuro--typewriter-timer))
        (kuro--start-typewriter-timer)
        (should (timerp kuro--typewriter-timer))
        (should-not (eq kuro--typewriter-timer first-timer)))
      (kuro--stop-typewriter-timer))))

;;; Group 9: defcustom defaults and rate calculation

(ert-deftest kuro-typewriter-negative-cps-clamped-to-one ()
  "kuro--start-typewriter-timer clamps negative CPS to 1 via (max 1 cps).
When kuro-typewriter-chars-per-second is -5, interval = 1.0/max(1,-5) = 1.0.
The result must be exactly 1.0 (not negative, not infinite)."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second -5)
          (captured nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (delay _repeat _fn)
                   (setq captured delay)
                   'fake-timer)))
        (kuro--start-typewriter-timer)
        ;; max(1, -5) = 1, so interval = 1.0/1 = 1.0
        (should (floatp captured))
        (should (< (abs (- captured 1.0)) 1e-10))))))

(ert-deftest kuro-typewriter-large-cps-produces-small-interval ()
  "kuro--start-typewriter-timer with 1000 CPS produces interval ≈ 0.001 seconds.
Verifies that large CPS values are NOT clamped and produce sub-millisecond intervals."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 1000)
          (captured nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (delay _repeat _fn)
                   (setq captured delay)
                   'fake-timer)))
        (kuro--start-typewriter-timer)
        ;; 1.0 / 1000 = 0.001
        (should (floatp captured))
        (should (< (abs (- captured 0.001)) 1e-10))))))

(ert-deftest kuro-typewriter-tick-with-nil-current-text-dequeues-next ()
  "kuro--typewriter-tick with nil current-text but non-empty queue dequeues next item.
When kuro--typewriter-current-text is nil the first cond branch is skipped;
kuro--typewriter-queue-next fires and sets state from the queued item."
  (kuro-typewriter-test--with-buffer
    (setq kuro--typewriter-current-row nil
          kuro--typewriter-current-text nil
          kuro--typewriter-written-len 0
          kuro--typewriter-queue (list (cons 3 "dequeued")))
    (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
               (lambda (_row _text) (error "write-partial must not be called on dequeue tick"))))
      (kuro--typewriter-tick)
      ;; queue-next should have dequeued (3 . "dequeued") and set state
      (should (= kuro--typewriter-current-row 3))
      (should (equal kuro--typewriter-current-text "dequeued"))
      (should (= kuro--typewriter-written-len 0))
      (should (null kuro--typewriter-queue)))))

(ert-deftest kuro-typewriter-effect-default-is-nil ()
  "kuro-typewriter-effect default value must be nil (effect is opt-in)."
  (should (null (default-value 'kuro-typewriter-effect))))

(ert-deftest kuro-typewriter-chars-per-second-default-is-positive ()
  "kuro-typewriter-chars-per-second default must be a positive integer."
  (let ((val (default-value 'kuro-typewriter-chars-per-second)))
    (should (integerp val))
    (should (> val 0))))

(ert-deftest kuro-typewriter-chars-per-second-default-is-120 ()
  "kuro-typewriter-chars-per-second default must be 120."
  (should (= (default-value 'kuro-typewriter-chars-per-second) 120)))

(ert-deftest kuro-typewriter-start-timer-uses-chars-per-second-for-interval ()
  "kuro--start-typewriter-timer uses 1.0/kuro-typewriter-chars-per-second as interval.
At 60 cps the interval should be 1/60 seconds."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 60)
          (captured nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (delay repeat fn)
                   (setq captured (list delay repeat fn))
                   'fake-timer)))
        (kuro--start-typewriter-timer)
        (should captured)
        (let ((interval (car captured)))
          (should (floatp interval))
          (should (< (abs (- interval (/ 1.0 60))) 1e-10)))))))

(ert-deftest kuro-typewriter-start-timer-clamps-zero-cps-to-one ()
  "kuro--start-typewriter-timer uses max 1 as minimum CPS denominator.
When kuro-typewriter-chars-per-second is 0, interval = 1.0/max(1,0) = 1.0."
  (kuro-typewriter-test--with-buffer
    (let ((kuro-typewriter-effect t)
          (kuro-typewriter-chars-per-second 0)
          (captured nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (delay _repeat _fn)
                   (setq captured delay)
                   'fake-timer)))
        (kuro--start-typewriter-timer)
        ;; max(1, 0) = 1, so interval = 1.0
        (should (floatp captured))
        (should (< (abs (- captured 1.0)) 1e-10))))))

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

(provide 'kuro-typewriter-test)

;;; kuro-typewriter-test.el ends here
