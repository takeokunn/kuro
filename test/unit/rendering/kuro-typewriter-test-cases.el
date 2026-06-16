;;; kuro-typewriter-test-cases.el --- Typewriter test case data  -*- lexical-binding: t; -*-

;;; Commentary:
;; Data-only fixtures consumed by typewriter test macros.

;;; Code:

(defconst kuro-typewriter-test--tick-partial-write-cases
  '((kuro-typewriter-tick-writes-one-character
     "kuro--typewriter-tick advances written-len by 1 and writes the substring."
     "hello\n" 0 "hello" 5 2 3 "hel")
    (kuro-typewriter-tick-writes-from-beginning
     "kuro--typewriter-tick with written-len=0 writes the first character."
     "abc\n" 0 "abc" 3 0 1 "a")
    (kuro-typewriter-tick-single-character-text
     "A single-character text is written in one tick and leaves written-len = 1."
     "x\n" 0 "x" 1 0 1 "x")
    (kuro-typewriter-tick-partial-write-mid-row
     "kuro--typewriter-tick writes exactly one character when mid-row."
     "hello\n" 0 "hello" 5 3 4 "hell"))
  "Cases for partial writes performed by `kuro--typewriter-tick'.
Each case is (TEST-NAME DOC BUFFER ROW TEXT TEXT-LEN WRITTEN-LEN
EXPECTED-WRITTEN-LEN EXPECTED-PARTIAL-TEXT).")

(defconst kuro-typewriter-test--tick-no-write-state-cases
  '((kuro-typewriter-tick-does-not-advance-when-complete
     "kuro--typewriter-tick is a no-op (resets state) when written-len equals text length."
     t 0 "hi" 2 nil nil nil 0)
    (kuro-typewriter-tick-noop-when-no-current-and-empty-queue
     "kuro--typewriter-tick is a no-op when there is no current row and queue is empty."
     t nil nil 0 nil nil nil 0)
    (kuro-typewriter-tick-blocked-when-not-initialized
     "kuro--typewriter-tick does nothing when kuro--initialized is nil."
     nil 0 "text" 0 nil 0 "text" 0)
    (kuro-typewriter-tick-resets-state-when-queue-empty
     "kuro--typewriter-tick resets all state vars when queue is empty after completion."
     t 0 "xy" 2 nil nil nil 0)
    (kuro-typewriter-tick-noop-when-not-initialized
     "kuro--typewriter-tick is a no-op when kuro--initialized is nil."
     nil 2 "test" 1 nil 2 "test" 1)
    (kuro-typewriter-tick-empty-string-text-resets-state
     "kuro--typewriter-tick resets state immediately when current-text is empty string."
     t 0 "" 0 nil nil nil 0)
    (kuro-typewriter-tick-nil-text-falls-through-to-queue-next
     "kuro--typewriter-tick with current-row set but current-text nil falls through."
     t 0 nil 0 nil nil nil 0))
  "Cases where `kuro--typewriter-tick' must not write.
Each case is (TEST-NAME DOC INITIALIZED ROW TEXT WRITTEN-LEN QUEUE
EXPECTED-ROW EXPECTED-TEXT EXPECTED-WRITTEN-LEN).")

(defconst kuro-typewriter-test--timer-interval-cases
  '((kuro-typewriter-negative-cps-clamped-to-one
     "kuro--start-typewriter-timer clamps negative CPS to a 1.0 second interval."
     -5 1.0)
    (kuro-typewriter-large-cps-produces-small-interval
     "kuro--start-typewriter-timer preserves large CPS values as small intervals."
     1000 0.001)
    (kuro-typewriter-start-timer-uses-chars-per-second-for-interval
     "kuro--start-typewriter-timer uses 1.0/kuro-typewriter-chars-per-second."
     60 (/ 1.0 60))
    (kuro-typewriter-start-timer-clamps-zero-cps-to-one
     "kuro--start-typewriter-timer clamps zero CPS to a 1.0 second interval."
     0 1.0))
  "Cases for typewriter timer interval calculation.
Each case is (TEST-NAME DOC CPS EXPECTED-INTERVAL).")

(defconst kuro-typewriter-test--default-value-cases
  '((kuro-typewriter-effect-default-is-nil
     "kuro-typewriter-effect default value must be nil."
     kuro-typewriter-effect
     (lambda (value) (null value)))
    (kuro-typewriter-chars-per-second-default-is-positive
     "kuro-typewriter-chars-per-second default must be a positive integer."
     kuro-typewriter-chars-per-second
     (lambda (value) (and (integerp value) (> value 0))))
    (kuro-typewriter-chars-per-second-default-is-120
     "kuro-typewriter-chars-per-second default must be 120."
     kuro-typewriter-chars-per-second
     (lambda (value) (= value 120))))
  "Cases for typewriter defcustom default value invariants.
Each case is (TEST-NAME DOC VARIABLE CHECKER).")

(provide 'kuro-typewriter-test-cases)

;;; kuro-typewriter-test-cases.el ends here
