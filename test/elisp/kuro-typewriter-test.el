;;; kuro-typewriter-test.el --- Unit tests for kuro-typewriter.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-typewriter.el (typewriter animation effect).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Covered:
;;   - kuro--typewriter-tick: basic character advancement
;;   - kuro--typewriter-tick: empty queue / nothing to write
;;   - kuro--typewriter-tick: completion when written-len equals text length
;;   - kuro--typewriter-tick: single-character text written in one tick
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

(ert-deftest kuro-typewriter-queue-next-fifo-order ()
  "kuro--typewriter-queue-next pops items in FIFO order (last of list = first enqueued)."
  (kuro-typewriter-test--with-buffer
    ;; push builds the queue in reverse; last is the oldest (FIFO front)
    (setq kuro--typewriter-queue (list (cons 5 "second") (cons 3 "first")))
    (kuro--typewriter-queue-next)
    ;; car (last) of the list: (3 . "first") is the FIFO front
    (should (= kuro--typewriter-current-row 3))
    (should (equal kuro--typewriter-current-text "first"))))

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

(provide 'kuro-typewriter-test)

;;; kuro-typewriter-test.el ends here
