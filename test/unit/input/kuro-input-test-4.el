;;; kuro-input-test-4.el --- Tests for kuro-input.el — Groups 19-22  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-test-support)

;;; Group 19: kuro--schedule-immediate-render — timer coalescing and creation

(ert-deftest kuro-input-schedule-immediate-render-cancels-existing-timer ()
  "kuro--schedule-immediate-render cancels any existing pending-render-timer first.
If kuro--pending-render-timer is already a timer, cancel-timer must be called
before the new idle timer is created."
  (with-temp-buffer
    (let ((cancel-called-with nil)
          (fake-old (cons 'fake-timer nil)))
      (setq-local kuro--pending-render-timer fake-old)
      ;; Make timerp return t for our fake timer
      (cl-letf (((symbol-function 'timerp)
                 (lambda (x) (eq x fake-old)))
                ((symbol-function 'cancel-timer)
                 (lambda (x) (setq cancel-called-with x)))
                ((symbol-function 'run-with-idle-timer)
                 (lambda (_delay _repeat _fn &rest _args) 'new-fake-timer)))
        (kuro--schedule-immediate-render)
        (should (eq cancel-called-with fake-old))))))

(ert-deftest kuro-input-schedule-immediate-render-sets-pending-timer ()
  "kuro--schedule-immediate-render stores the new timer in kuro--pending-render-timer."
  (with-temp-buffer
    (setq-local kuro--pending-render-timer nil)
    (cl-letf (((symbol-function 'timerp) (lambda (_x) nil))
              ((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat _fn &rest _args) 'created-timer)))
      (kuro--schedule-immediate-render)
      (should (eq kuro--pending-render-timer 'created-timer)))))

(ert-deftest kuro-input-schedule-immediate-render-uses-echo-delay ()
  "kuro--schedule-immediate-render passes kuro-input-echo-delay to run-with-idle-timer."
  (with-temp-buffer
    (setq-local kuro--pending-render-timer nil)
    (let ((kuro-input-echo-delay 0.042)
          (captured-delay nil))
      (cl-letf (((symbol-function 'timerp) (lambda (_x) nil))
                ((symbol-function 'run-with-idle-timer)
                 (lambda (delay _repeat _fn &rest _args)
                   (setq captured-delay delay)
                   'fake)))
        (kuro--schedule-immediate-render)
        (should (= captured-delay 0.042))))))

;;; Group 20: kuro--encode-key-event — edge cases not yet covered

(ert-deftest kuro-input-encode-key-ctrl-non-char-base-returns-nil ()
  "kuro--encode-key-event returns nil when modifier is control but base is a symbol.
The control branch requires (characterp base); if base is e.g. 'f15 (non-char),
none of the character branches match and assq lookup also fails → nil."
  (cl-letf (((symbol-function 'event-modifiers)
             (lambda (_ev) '(control)))
            ((symbol-function 'event-basic-type)
             (lambda (_ev) 'f15)))
    (should-not (kuro--encode-key-event 'C-f15))))

(ert-deftest kuro-input-encode-key-meta-non-char-base-returns-nil ()
  "kuro--encode-key-event returns nil when modifier is meta but base is a symbol.
The meta branch requires (characterp base); non-character symbols fall through
all cond branches and produce nil."
  (cl-letf (((symbol-function 'event-modifiers)
             (lambda (_ev) '(meta)))
            ((symbol-function 'event-basic-type)
             (lambda (_ev) 'f15)))
    (should-not (kuro--encode-key-event 'M-f15))))

(ert-deftest kuro-input-encode-key-ctrl-meta-non-char-base-returns-nil ()
  "kuro--encode-key-event returns nil when both control+meta are set but base is a symbol."
  (cl-letf (((symbol-function 'event-modifiers)
             (lambda (_ev) '(control meta)))
            ((symbol-function 'event-basic-type)
             (lambda (_ev) 'home)))
    (should-not (kuro--encode-key-event 'C-M-home))))

;;; Group 21: kuro--kitty-modifier-offset constant and Kitty encoding invariants

(ert-deftest kuro-input-kitty-modifier-offset-value ()
  "kuro--kitty-modifier-offset is 1 (the +1 added to the wire modifier bitmask)."
  (should (= kuro--kitty-modifier-offset 1)))

(ert-deftest kuro-input-encode-kitty-key-shift-modifier ()
  "kuro--encode-kitty-key with shift (bitmask 1) produces modifier param 2."
  ;; shift=1 → wire = 1 + kuro--kitty-modifier-offset = 2
  (should (equal (kuro--encode-kitty-key 65 1) "\e[65;2u")))

(ert-deftest kuro-input-encode-kitty-key-all-common-modifiers ()
  "kuro--encode-kitty-key with ctrl+alt (bitmask 6) produces modifier param 7."
  ;; ctrl=4, alt=2 → bitmask = 6 → wire = 6 + 1 = 7
  (should (equal (kuro--encode-kitty-key 65 6) "\e[65;7u")))

;;; Group 22: scroll offset fallback (kuro--get-scroll-offset returns nil)

(ert-deftest kuro-input-scroll-up-offset-fallback-when-ffi-returns-nil ()
  "kuro-scroll-up uses (+ scroll-offset lines) when kuro--get-scroll-offset returns nil."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () nil)            ; FFI returns nil → fallback arithmetic
    (setq kuro--scroll-offset 10)
    (cl-letf (((symbol-function 'window-body-height) (lambda () 5)))
      (kuro-scroll-up))
    ;; Fallback: 10 + 5 = 15
    (should (= kuro--scroll-offset 15))))

(ert-deftest kuro-input-scroll-down-offset-fallback-when-ffi-returns-nil ()
  "kuro-scroll-down uses max(0, scroll-offset - lines) when kuro--get-scroll-offset returns nil."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () nil)            ; FFI returns nil → fallback arithmetic
    (setq kuro--scroll-offset 10)
    (cl-letf (((symbol-function 'window-body-height) (lambda () 3)))
      (kuro-scroll-down))
    ;; Fallback: max(0, 10 - 3) = 7
    (should (= kuro--scroll-offset 7))))

(ert-deftest kuro-input-scroll-down-offset-fallback-clamps-to-zero ()
  "kuro-scroll-down fallback clamps offset to 0 when lines > current offset."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () nil)
    (setq kuro--scroll-offset 2)
    (cl-letf (((symbol-function 'window-body-height) (lambda () 10)))
      (kuro-scroll-down))
    ;; max(0, 2 - 10) = max(0, -8) = 0
    (should (= kuro--scroll-offset 0))))

(provide 'kuro-input-test-4)
;;; kuro-input-test-4.el ends here
