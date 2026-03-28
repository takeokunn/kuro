;;; kuro-input-ext-test.el --- Unit tests for kuro-input.el (Groups 18-30)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-input.el — scroll, key encoding, buffer-local vars,
;; Kitty key encoding, and send-char / def-special-key.
;; Split from kuro-input-test.el at the Group 18 boundary.
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input)

;;; Helper

(defmacro kuro-input-test--capture-sent (&rest body)
  "Execute BODY with kuro--send-key stubbed; return list of sent strings."
  `(let ((sent nil)
         (kuro--initialized t))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (push s sent))))
       ,@body)
     (nreverse sent)))

;;; Group 18: kuro-scroll-up / kuro-scroll-down / kuro-scroll-bottom

(defmacro kuro-input-test--with-scroll-stubs (scroll-up-fn scroll-down-fn
                                              get-offset-fn &rest body)
  "Run BODY with scroll FFI functions stubbed and kuro--initialized=t."
  (declare (indent 3))
  `(with-temp-buffer
     (setq-local kuro--initialized t
                 kuro--scroll-offset 0)
     (cl-letf (((symbol-function 'kuro--scroll-up)    ,scroll-up-fn)
               ((symbol-function 'kuro--scroll-down)  ,scroll-down-fn)
               ((symbol-function 'kuro--get-scroll-offset) ,get-offset-fn)
               ((symbol-function 'kuro--render-cycle) #'ignore))
       ,@body)))

(ert-deftest kuro-input-scroll-up-calls-ffi ()
  "kuro-scroll-up calls kuro--scroll-up with window-body-height lines."
  (let ((up-called-with nil))
    (kuro-input-test--with-scroll-stubs
        (lambda (n) (setq up-called-with n))
        #'ignore
        (lambda () nil)
      (cl-letf (((symbol-function 'window-body-height) (lambda () 24)))
        (kuro-scroll-up))
      (should (= up-called-with 24)))))

(ert-deftest kuro-input-scroll-up-noop-when-uninitialized ()
  "kuro-scroll-up does nothing when kuro--initialized is nil."
  (let ((up-called nil))
    (with-temp-buffer
      (setq-local kuro--initialized nil
                  kuro--scroll-offset 0)
      (cl-letf (((symbol-function 'kuro--scroll-up)
                 (lambda (_n) (setq up-called t))))
        (kuro-scroll-up))
      (should-not up-called))))

(ert-deftest kuro-input-scroll-down-calls-ffi ()
  "kuro-scroll-down calls kuro--scroll-down with window-body-height lines."
  (let ((down-called-with nil))
    (kuro-input-test--with-scroll-stubs
        #'ignore
        (lambda (n) (setq down-called-with n))
        (lambda () nil)
      (cl-letf (((symbol-function 'window-body-height) (lambda () 24)))
        (kuro-scroll-down))
      (should (= down-called-with 24)))))

(ert-deftest kuro-input-scroll-down-noop-when-uninitialized ()
  "kuro-scroll-down does nothing when kuro--initialized is nil."
  (let ((down-called nil))
    (with-temp-buffer
      (setq-local kuro--initialized nil
                  kuro--scroll-offset 5)
      (cl-letf (((symbol-function 'kuro--scroll-down)
                 (lambda (_n) (setq down-called t))))
        (kuro-scroll-down))
      (should-not down-called))))

(ert-deftest kuro-input-scroll-bottom-calls-ffi-with-sentinel ()
  "kuro-scroll-bottom calls kuro--scroll-down with the sentinel value."
  (let ((down-called-with nil))
    (kuro-input-test--with-scroll-stubs
        #'ignore
        (lambda (n) (setq down-called-with n))
        (lambda () 0)
      (kuro-scroll-bottom))
    (should (= down-called-with kuro--scroll-to-bottom-sentinel))))

(ert-deftest kuro-input-scroll-bottom-resets-offset ()
  "kuro-scroll-bottom resets kuro--scroll-offset to 0 (via kuro--get-scroll-offset)."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () 0)
    (setq kuro--scroll-offset 42)
    (kuro-scroll-bottom)
    (should (= kuro--scroll-offset 0))))

(ert-deftest kuro-input-scroll-bottom-noop-when-uninitialized ()
  "kuro-scroll-bottom does nothing when kuro--initialized is nil."
  (let ((down-called nil))
    (with-temp-buffer
      (setq-local kuro--initialized nil
                  kuro--scroll-offset 10)
      (cl-letf (((symbol-function 'kuro--scroll-down)
                 (lambda (_n) (setq down-called t))))
        (kuro-scroll-bottom))
      (should-not down-called))))

;;; Group 14: kuro--named-key-sequences data table

(ert-deftest kuro-input-named-key-sequences-is-alist ()
  "kuro--named-key-sequences is a non-empty alist of (symbol . string) pairs."
  (should (consp kuro--named-key-sequences))
  (dolist (entry kuro--named-key-sequences)
    (should (symbolp (car entry)))
    (should (stringp (cdr entry)))))

(ert-deftest kuro-input-named-key-return-maps-to-cr ()
  "kuro--named-key-sequences maps `return' to carriage return."
  (should (equal (cdr (assq 'return kuro--named-key-sequences)) "\r")))

(ert-deftest kuro-input-named-key-tab-maps-to-ht ()
  "kuro--named-key-sequences maps `tab' to horizontal tab."
  (should (equal (cdr (assq 'tab kuro--named-key-sequences)) "\t")))

(ert-deftest kuro-input-named-key-backspace-maps-to-del ()
  "kuro--named-key-sequences maps `backspace' to DEL (\\x7f)."
  (should (equal (cdr (assq 'backspace kuro--named-key-sequences)) "\x7f")))

(ert-deftest kuro-input-named-key-escape-maps-to-esc ()
  "kuro--named-key-sequences maps `escape' to ESC (\\e)."
  (should (equal (cdr (assq 'escape kuro--named-key-sequences)) "\e")))

;;; Group 15: kuro--encode-key-event

(ert-deftest kuro-input-encode-key-ctrl-meta-char ()
  "Control+Meta+char encodes as ESC + control byte (C-M-a → ESC ^A)."
  ;; Simulate C-M-a: modifiers=(control meta), base=?a
  (let ((event (list 'C-M-a)))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(control meta)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string ?\e (logand ?a 31)))))))

(ert-deftest kuro-input-encode-key-ctrl-char ()
  "Control+char encodes as a single control byte (C-a → ^A = \\x01)."
  (let ((event 'C-a))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(control)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string (logand ?a 31)))))))

(ert-deftest kuro-input-encode-key-meta-char ()
  "Meta+char encodes as ESC + the base character (M-a → ESC a)."
  (let ((event 'M-a))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(meta)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string ?\e ?a))))))

(ert-deftest kuro-input-encode-key-plain-char ()
  "Plain character encodes as itself."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) ?z)))
    (should (equal (kuro--encode-key-event 'z) (string ?z)))))

(ert-deftest kuro-input-encode-key-return ()
  "Named key `return' encodes as carriage return."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'return)))
    (should (equal (kuro--encode-key-event 'return) "\r"))))

(ert-deftest kuro-input-encode-key-tab ()
  "Named key `tab' encodes as horizontal tab."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'tab)))
    (should (equal (kuro--encode-key-event 'tab) "\t"))))

(ert-deftest kuro-input-encode-key-backspace ()
  "Named key `backspace' encodes as DEL (\\x7f)."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'backspace)))
    (should (equal (kuro--encode-key-event 'backspace) "\x7f"))))

(ert-deftest kuro-input-encode-key-escape ()
  "Named key `escape' encodes as ESC."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'escape)))
    (should (equal (kuro--encode-key-event 'escape) "\e"))))

(ert-deftest kuro-input-encode-key-unsupported-returns-nil ()
  "An unrecognised key symbol encodes as nil."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'f13)))
    (should-not (kuro--encode-key-event 'f13))))

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
                 (lambda (_delay _repeat _fn) 'new-fake-timer)))
        (kuro--schedule-immediate-render)
        (should (eq cancel-called-with fake-old))))))

(ert-deftest kuro-input-schedule-immediate-render-sets-pending-timer ()
  "kuro--schedule-immediate-render stores the new timer in kuro--pending-render-timer."
  (with-temp-buffer
    (setq-local kuro--pending-render-timer nil)
    (cl-letf (((symbol-function 'timerp) (lambda (_x) nil))
              ((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat _fn) 'created-timer)))
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
                 (lambda (delay _repeat _fn)
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

(provide 'kuro-input-ext-test)

;;; kuro-input-ext-test.el ends here
