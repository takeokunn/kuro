;;; kuro-typewriter-test-2.el --- Unit tests for kuro-typewriter.el — Groups 5-9  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-typewriter-test-support)

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

(provide 'kuro-typewriter-test-2)

;;; kuro-typewriter-test-2.el ends here
