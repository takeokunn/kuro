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

(provide 'kuro-typewriter-test)

;;; kuro-typewriter-test.el ends here
