;;; kuro-renderer-test-2.el --- ERT tests for kuro-renderer — Groups 10-14  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-renderer-test-support)

;;; Group 10: kuro--handle-clipboard-actions

(ert-deftest kuro-renderer-handle-clipboard-write-only-policy-calls-kill-new ()
  "kuro--handle-clipboard-actions calls kill-new for write actions under write-only policy."
  (kuro-renderer-helpers-test--with-buffer
    (let ((kill-new-called-with nil)
          (kuro-clipboard-policy 'write-only))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "hello from terminal"))))
                ((symbol-function 'kill-new)
                 (lambda (text) (setq kill-new-called-with text)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (equal kill-new-called-with "hello from terminal"))))))

(ert-deftest kuro-renderer-handle-clipboard-allow-policy-calls-kill-new ()
  "kuro--handle-clipboard-actions calls kill-new for write actions under allow policy."
  (kuro-renderer-helpers-test--with-buffer
    (let ((kill-new-called nil)
          (kuro-clipboard-policy 'allow))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "data"))))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should kill-new-called)))))

(ert-deftest kuro-renderer-handle-clipboard-deny-policy-does-not-call-kill-new ()
  "kuro--handle-clipboard-actions does NOT call kill-new under an unknown/deny policy."
  (kuro-renderer-helpers-test--with-buffer
    (let ((kill-new-called nil)
          ;; 'deny is not a defined policy value; the pcase falls through
          ;; without matching any branch, so kill-new must never be called.
          (kuro-clipboard-policy 'deny))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "secret"))))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should-not kill-new-called)))))

(ert-deftest kuro-renderer-handle-clipboard-write-only-blocks-query ()
  "kuro--handle-clipboard-actions does NOT respond to query actions under write-only policy."
  (kuro-renderer-helpers-test--with-buffer
    (let ((send-key-called nil)
          (kuro-clipboard-policy 'write-only))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query))))
                ((symbol-function 'kuro--send-key)
                 (lambda (_s) (setq send-key-called t))))
        (kuro--handle-clipboard-actions)
        (should-not send-key-called)))))

(ert-deftest kuro-renderer-handle-clipboard-empty-actions-noop ()
  "kuro--handle-clipboard-actions is a no-op when the action list is nil."
  (kuro-renderer-helpers-test--with-buffer
    (let ((kill-new-called nil))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () nil))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should-not kill-new-called)))))

(ert-deftest kuro-renderer-handle-clipboard-multiple-write-actions ()
  "kuro--handle-clipboard-actions processes multiple write actions in sequence."
  (kuro-renderer-helpers-test--with-buffer
    (let ((killed-texts nil)
          (kuro-clipboard-policy 'write-only))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "first") (write . "second"))))
                ((symbol-function 'kill-new)
                 (lambda (text) (push text killed-texts)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (= (length killed-texts) 2))
        (should (member "first" killed-texts))
        (should (member "second" killed-texts))))))

;;; Group 10b: Blink overlay clearing during line update

(ert-deftest test-kuro-update-line-full-clears-blink-overlays-on-row ()
  "Updating a line removes blink overlays on that row."
  (with-temp-buffer
    (insert "old text\n")
    (insert "other row\n")
    (let ((kuro--blink-overlays nil)
          (kuro--blink-overlays-by-row nil)
          (kuro--image-overlays nil)
          (kuro--col-to-buf-map (make-hash-table :test 'eql)))
      ;; Create a blink overlay on row 0
      (let ((ov (make-overlay 1 5)))
        (overlay-put ov 'kuro-blink t)
        (overlay-put ov 'kuro-blink-type 'slow)
        (push ov kuro--blink-overlays))
      ;; Update row 0 — should clear blink overlay on that row
      (kuro--update-line-full 0 "new text" nil nil)
      (should (null kuro--blink-overlays)))))

(ert-deftest test-kuro-update-line-full-preserves-blink-overlays-other-row ()
  "Updating a line preserves blink overlays on other rows."
  (with-temp-buffer
    (insert "row zero\n")
    (insert "row one\n")
    (let ((kuro--blink-overlays nil)
          (kuro--image-overlays nil)
          (kuro--col-to-buf-map (make-hash-table :test 'eql)))
      ;; Create a blink overlay on row 1
      (let ((ov (make-overlay 10 15)))
        (overlay-put ov 'kuro-blink t)
        (overlay-put ov 'kuro-blink-type 'fast)
        (push ov kuro--blink-overlays))
      ;; Update row 0 — should NOT clear blink overlay on row 1
      (kuro--update-line-full 0 "new text" nil nil)
      (should (= 1 (length kuro--blink-overlays))))))

;;; Group 12: kuro--install-render-timer

(ert-deftest kuro-renderer-install-render-timer-creates-timer ()
  "kuro--install-render-timer creates a live timer object."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    (kuro--install-render-timer 30)
    (should (timerp kuro--timer))
    (cancel-timer kuro--timer)
    (setq kuro--timer nil)))

(ert-deftest kuro-renderer-install-render-timer-cancels-existing ()
  "kuro--install-render-timer cancels any pre-existing timer before installing.
Verification: after a second install the old timer is no longer in `timer-list'."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    ;; Install a first timer.
    (kuro--install-render-timer 30)
    (let ((first kuro--timer))
      ;; Install a second timer — must cancel the first.
      (kuro--install-render-timer 60)
      ;; The new timer must differ from the first.
      (should-not (eq kuro--timer first))
      ;; The first timer must no longer be in the active timer list.
      (should-not (memq first timer-list))
      (cancel-timer kuro--timer)
      (setq kuro--timer nil))))

(ert-deftest kuro-renderer-install-render-timer-interval-from-rate ()
  "kuro--install-render-timer sets the repeat interval to 1/rate seconds."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    (kuro--install-render-timer 60)
    ;; timer--repeat-delay holds the repeat interval.
    (let ((interval (timer--repeat-delay kuro--timer)))
      (should (floatp interval))
      ;; 1/60 ≈ 0.01667 — allow 1% tolerance.
      (should (< (abs (- interval (/ 1.0 60))) 0.001)))
    (cancel-timer kuro--timer)
    (setq kuro--timer nil)))

(ert-deftest kuro-renderer-install-render-timer-nil-when-no-prior ()
  "kuro--install-render-timer with no pre-existing timer does not error."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    (should-not (condition-case err
                    (progn (kuro--install-render-timer 30) nil)
                  (error err)))
    (cancel-timer kuro--timer)
    (setq kuro--timer nil)))

;;; Group 13: kuro--reset-cursor-cache macro

(ert-deftest kuro-renderer-reset-cursor-cache-clears-all-four-fields ()
  "kuro--reset-cursor-cache sets all four cursor cache vars to nil."
  (with-temp-buffer
    (let ((kuro--last-cursor-row    5)
          (kuro--last-cursor-col    10)
          (kuro--last-cursor-visible t)
          (kuro--last-cursor-shape  'box))
      (kuro--reset-cursor-cache)
      (should (null kuro--last-cursor-row))
      (should (null kuro--last-cursor-col))
      (should (null kuro--last-cursor-visible))
      (should (null kuro--last-cursor-shape)))))

(ert-deftest kuro-renderer-reset-cursor-cache-idempotent ()
  "Calling kuro--reset-cursor-cache twice is safe and keeps all vars nil."
  (with-temp-buffer
    (let ((kuro--last-cursor-row    3)
          (kuro--last-cursor-col    7)
          (kuro--last-cursor-visible t)
          (kuro--last-cursor-shape  '(hbar . 2)))
      (kuro--reset-cursor-cache)
      (kuro--reset-cursor-cache)
      (should (null kuro--last-cursor-row))
      (should (null kuro--last-cursor-col))
      (should (null kuro--last-cursor-visible))
      (should (null kuro--last-cursor-shape)))))

(ert-deftest kuro-renderer-reset-cursor-cache-already-nil-is-noop ()
  "kuro--reset-cursor-cache with all fields already nil does not error."
  (with-temp-buffer
    (let (kuro--last-cursor-row
          kuro--last-cursor-col
          kuro--last-cursor-visible
          kuro--last-cursor-shape)
      (should-not (condition-case err
                      (progn (kuro--reset-cursor-cache) nil)
                    (error err))))))

;;; Group 14: kuro--sanitize-title edge cases

(ert-deftest kuro-renderer-sanitize-title-strips-rlm ()
  "kuro--sanitize-title strips U+200F RIGHT-TO-LEFT MARK."
  (should (equal (kuro--sanitize-title (concat "a" "\u200f" "b")) "ab")))

(ert-deftest kuro-renderer-sanitize-title-strips-null-byte ()
  "kuro--sanitize-title strips embedded null bytes (U+0000)."
  (should (equal (kuro--sanitize-title (concat "a" (string 0) "b")) "ab")))

(ert-deftest kuro-renderer-sanitize-title-strips-tab ()
  "kuro--sanitize-title strips TAB (U+0009, a C0 control char)."
  (should (equal (kuro--sanitize-title (concat "a" (string 9) "b")) "ab")))

(ert-deftest kuro-renderer-sanitize-title-all-bidi-overrides ()
  "kuro--sanitize-title strips the full U+202A-U+202E bidi override range."
  (dolist (cp '(#x202a #x202b #x202c #x202d #x202e))
    (should (equal (kuro--sanitize-title (concat "x" (string cp) "y")) "xy"))))

(ert-deftest kuro-renderer-sanitize-title-all-isolates ()
  "kuro--sanitize-title strips the full U+2066-U+2069 directional isolate range."
  (dolist (cp '(#x2066 #x2067 #x2068 #x2069))
    (should (equal (kuro--sanitize-title (concat "x" (string cp) "y")) "xy"))))

(ert-deftest kuro-renderer-sanitize-title-preserves-unicode-non-bidi ()
  "kuro--sanitize-title passes through harmless non-ASCII Unicode unchanged."
  (should (equal (kuro--sanitize-title "日本語") "日本語"))
  (should (equal (kuro--sanitize-title "émoji 🎉") "émoji 🎉")))

(ert-deftest test-kuro-update-line-full-nil-col-to-buf-removes-stale ()
  "Nil col-to-buf removes stale mapping from hash table."
  (with-temp-buffer
    (insert "test line\n")
    (let ((kuro--blink-overlays nil)
          (kuro--image-overlays nil)
          (kuro--col-to-buf-map (make-hash-table :test 'eql)))
      ;; Pre-populate stale CJK mapping for row 0
      (puthash 0 [0 0 1 1 2 2] kuro--col-to-buf-map)
      ;; Update with nil col-to-buf (pure ASCII line)
      (kuro--update-line-full 0 "ascii" nil nil)
      ;; Stale mapping should be removed
      (should (null (gethash 0 kuro--col-to-buf-map))))))

(ert-deftest test-kuro-update-line-full-vector-col-to-buf-stores ()
  "Vector col-to-buf is stored in hash table."
  (with-temp-buffer
    (insert "test line\n")
    (let ((kuro--blink-overlays nil)
          (kuro--image-overlays nil)
          (kuro--col-to-buf-map (make-hash-table :test 'eql)))
      ;; Update with a vector col-to-buf
      (kuro--update-line-full 0 "日本" nil [0 0 1 1])
      ;; Mapping should be stored
      (should (equal (gethash 0 kuro--col-to-buf-map) [0 0 1 1])))))

;;; Group 25: kuro--timed, kuro--pipeline-face-count, kuro--pipeline-step-apply

(ert-deftest kuro-renderer-timed-returns-body-value ()
  "kuro--timed returns the value produced by body."
  (let ((ms 0))
    (should (eq 42 (kuro--timed ms 42)))))

(ert-deftest kuro-renderer-timed-sets-ms-var ()
  "kuro--timed sets the ms variable to a non-negative number."
  (let ((ms 0))
    (kuro--timed ms (sit-for 0))
    (should (>= ms 0.0))))

(ert-deftest kuro-renderer-timed-body-side-effects-execute ()
  "kuro--timed executes body so its side effects take effect."
  (let ((ms 0) (ran nil))
    (kuro--timed ms (setq ran t))
    (should ran)))

(ert-deftest kuro-renderer-pipeline-face-count-nil-returns-zero ()
  "kuro--pipeline-face-count returns 0 for a nil updates list."
  (should (= 0 (kuro--pipeline-face-count nil))))

(ert-deftest kuro-renderer-pipeline-face-count-counts-faces ()
  "kuro--pipeline-face-count sums face-range counts across all updates.
face-ranges is a stride-6 flat vector: (/ (length fr) 6) gives the count.
Row 0 has 2 ranges (12 elements) and row 1 has 3 ranges (18 elements) = 5 total."
  ;; updates is a vector of flat [row text face-ranges col-to-buf] entries.
  (let ((updates (vector (vector 0 "a" (make-vector 12 0) [])
                         (vector 1 "b" (make-vector 18 0) []))))
    (should (= 5 (kuro--pipeline-face-count updates)))))

(ert-deftest kuro-renderer-pipeline-step-apply-skips-nil ()
  "kuro--pipeline-step-apply does not call kuro--apply-dirty-lines for nil."
  (let ((called 0))
    (cl-letf (((symbol-function 'kuro--apply-dirty-lines)
               (lambda (&rest _) (cl-incf called))))
      (kuro--pipeline-step-apply nil)
      (should (= 0 called)))))

(ert-deftest kuro-renderer-pipeline-step-apply-calls-dirty-lines-when-non-nil ()
  "kuro--pipeline-step-apply calls kuro--apply-dirty-lines with the update list."
  (let* ((updates (vector (vector 0 "abc" [] [])))
         (received nil))
    (cl-letf (((symbol-function 'kuro--apply-dirty-lines)
               (lambda (ul) (setq received ul))))
      (kuro--pipeline-step-apply updates)
      (should (eq received updates)))))

(ert-deftest kuro-renderer-pipeline-step-apply-returns-nil-for-nil ()
  "kuro--pipeline-step-apply returns nil (from `when') for a nil update-list."
  (cl-letf (((symbol-function 'kuro--apply-dirty-lines) #'ignore))
    (should (null (kuro--pipeline-step-apply nil)))))

;;; kuro--reset-cursor-cache structural tests (Group 13 ext.)

(ert-deftest kuro-renderer-reset-cursor-cache-expands-to-setq ()
  "`kuro--reset-cursor-cache' single-step expands to a `setq' form."
  (let ((exp (macroexpand-1 '(kuro--reset-cursor-cache))))
    (should (eq (car exp) 'setq))))

(ert-deftest kuro-renderer-reset-cursor-cache-first-target-is-cursor-row ()
  "`kuro--reset-cursor-cache' first assignment target is `kuro--last-cursor-row'."
  (let ((exp (macroexpand-1 '(kuro--reset-cursor-cache))))
    (should (eq (cadr exp) 'kuro--last-cursor-row))))

(ert-deftest kuro-renderer-reset-cursor-cache-clears-all-four-vars ()
  "`kuro--reset-cursor-cache' expansion contains all four cache variable names."
  (let ((exp (macroexpand-1 '(kuro--reset-cursor-cache))))
    (should (memq 'kuro--last-cursor-row     exp))
    (should (memq 'kuro--last-cursor-col     exp))
    (should (memq 'kuro--last-cursor-visible exp))
    (should (memq 'kuro--last-cursor-shape   exp))))

;;; kuro--timed structural tests (Group 25 ext.)

(ert-deftest kuro-renderer-timed-expands-to-let ()
  "`kuro--timed' single-step expands to a `let' form."
  (let ((exp (macroexpand-1 '(kuro--timed ms (+ 1 2)))))
    (should (eq (car exp) 'let))))

(ert-deftest kuro-renderer-timed-binding-uses-private-name ()
  "`kuro--timed' binds `--timed-start' to prevent BODY shadowing."
  (let* ((exp (macroexpand-1 '(kuro--timed ms (ignore))))
         (binding-name (car (caadr exp))))
    (should (eq binding-name '--timed-start))))

(ert-deftest kuro-renderer-timed-body-wrapped-in-prog1 ()
  "`kuro--timed' wraps BODY in `prog1' to preserve the return value."
  (let* ((exp (macroexpand-1 '(kuro--timed ms (+ 1 2))))
         (body-form (caddr exp)))
    (should (eq (car body-form) 'prog1))))

(provide 'kuro-renderer-test-2)
;;; kuro-renderer-test-2.el ends here
