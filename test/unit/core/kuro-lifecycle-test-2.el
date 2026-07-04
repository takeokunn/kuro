;;; kuro-lifecycle-test-2.el --- kuro-lifecycle-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-lifecycle-test-support)

;;; ── Group 7: kuro--cleanup-render-state ────────────────────────────────────

(ert-deftest kuro-lifecycle--cleanup-render-state-resets-tui-counters ()
  "kuro--cleanup-render-state resets TUI mode counters to nil/0."
  (with-temp-buffer
    (setq-local kuro--tui-mode-active     t
                kuro--tui-mode-frame-count 5
                kuro--last-dirty-count    42)
    (cl-letf (((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil)))
      (kuro--cleanup-render-state)
      (should-not kuro--tui-mode-active)
      (should (= kuro--tui-mode-frame-count 0))
      (should (= kuro--last-dirty-count 0)))))

(ert-deftest kuro-lifecycle--cleanup-render-state-clears-blink-overlays ()
  "kuro--cleanup-render-state removes blink overlays and nil-ifies the list."
  (with-temp-buffer
    (insert "text\n")
    (let ((ov (make-overlay 1 3)))
      (overlay-put ov 'kuro-blink t)
      (setq-local kuro--blink-overlays (list ov)))
    (cl-letf (((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil)))
      (kuro--cleanup-render-state)
      (should (null kuro--blink-overlays)))))

(ert-deftest kuro-lifecycle--cleanup-render-state-resets-mouse-state ()
  "kuro--cleanup-render-state resets mouse-mode, mouse-sgr, mouse-pixel-mode."
  (with-temp-buffer
    (setq-local kuro--mouse-mode       1003
                kuro--mouse-sgr        t
                kuro--mouse-pixel-mode t)
    (cl-letf (((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil)))
      (kuro--cleanup-render-state)
      (should (= kuro--mouse-mode 0))
      (should (null kuro--mouse-sgr))
      (should (null kuro--mouse-pixel-mode)))))

(ert-deftest kuro-lifecycle--cleanup-render-state-resets-scroll-offset ()
  "kuro--cleanup-render-state resets scroll offset to 0."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 99)
    (cl-letf (((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil)))
      (kuro--cleanup-render-state)
      (should (= kuro--scroll-offset 0)))))

(ert-deftest kuro-lifecycle--cleanup-render-state-removes-font-remap ()
  "kuro--cleanup-render-state calls face-remap-remove-relative when cookie exists."
  (with-temp-buffer
    (setq-local kuro--font-remap-cookie 'fake-cookie)
    (let ((remove-called-with nil))
      (cl-letf (((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
                ((symbol-function 'face-remap-remove-relative)
                 (lambda (cookie) (setq remove-called-with cookie))))
        (kuro--cleanup-render-state)
        (should (eq remove-called-with 'fake-cookie))
        (should (null kuro--font-remap-cookie))))))

(ert-deftest kuro-lifecycle--cleanup-render-state-noop-font-remap-when-nil ()
  "kuro--cleanup-render-state does not call face-remap-remove-relative when cookie is nil."
  (with-temp-buffer
    (setq-local kuro--font-remap-cookie nil)
    (let ((remove-called nil))
      (cl-letf (((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
                ((symbol-function 'face-remap-remove-relative)
                 (lambda (_cookie) (setq remove-called t))))
        (kuro--cleanup-render-state)
        (should-not remove-called)))))

;;; ── Group 8: kuro--clear-session-state macro ────────────────────────────────

(ert-deftest kuro-lifecycle--clear-session-state-sets-initialized-nil ()
  "kuro--clear-session-state sets kuro--initialized to nil."
  (let ((kuro--initialized t)
        (kuro--session-id 42))
    (kuro--clear-session-state)
    (should-not kuro--initialized)))

(ert-deftest kuro-lifecycle--clear-session-state-sets-session-id-zero ()
  "kuro--clear-session-state sets kuro--session-id to 0."
  (let ((kuro--initialized t)
        (kuro--session-id 99))
    (kuro--clear-session-state)
    (should (= kuro--session-id 0))))

(ert-deftest kuro-lifecycle--clear-session-state-idempotent ()
  "Calling kuro--clear-session-state twice is safe and leaves state at nil/0."
  (let ((kuro--initialized t)
        (kuro--session-id 5))
    (kuro--clear-session-state)
    (kuro--clear-session-state)
    (should-not kuro--initialized)
    (should (= kuro--session-id 0))))

(ert-deftest kuro-lifecycle--clear-session-state-already-clear ()
  "kuro--clear-session-state is a no-op when state is already nil/0."
  (let ((kuro--initialized nil)
        (kuro--session-id 0))
    (should-not (condition-case err
                    (progn (kuro--clear-session-state) nil)
                  (error err)))
    (should-not kuro--initialized)
    (should (= kuro--session-id 0))))

;;; ── Group 9: kuro--def-control-key macro ────────────────────────────────────

(ert-deftest kuro-lifecycle-def-control-key-generates-interactive-command ()
  "kuro--def-control-key generates a bound, interactive defun."
  (should (fboundp 'kuro-send-interrupt))
  (should (fboundp 'kuro-send-sigstop))
  (should (fboundp 'kuro-send-sigquit))
  (should (commandp 'kuro-send-interrupt))
  (should (commandp 'kuro-send-sigstop))
  (should (commandp 'kuro-send-sigquit)))

(ert-deftest kuro-lifecycle-def-control-key-sends-correct-sequence ()
  "kuro-send-interrupt sends [?\\C-c] to the terminal."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (seq) (setq sent seq))))
      (kuro-send-interrupt)
      (should (equal sent [?\C-c])))))

;;; ── Group 10: kuro-list-sessions additional coverage ────────────────────────
;;
;; Covers the error path (kuro-core-list-sessions signals), multiple sessions,
;; and correct use of kuro--buffer-name-sessions.

(ert-deftest kuro-lifecycle--list-sessions-error-path-shows-empty-table ()
  "kuro-list-sessions treats an error from kuro-core-list-sessions as empty.
When the FFI call signals, condition-case in kuro-sessions--entries catches it
and returns nil, so the table is rendered with zero rows."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "module not loaded")))
            ((symbol-function 'display-buffer) #'ignore))
    (kuro-list-sessions)
    (let ((buf (get-buffer kuro--buffer-name-sessions)))
      (unwind-protect
          (progn
            (should (bufferp buf))
            (with-current-buffer buf
              (should (eq major-mode 'kuro-sessions-mode))
              (should (null (tabulated-list-get-id)))))
        (when buf (kill-buffer buf))))))

(ert-deftest kuro-lifecycle--list-sessions-multiple-sessions-all-present ()
  "kuro-list-sessions renders all entries when multiple sessions are returned."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda ()
               '((0 "bash"    nil t)
                 (1 "fish"    t   t)
                 (2 "/bin/sh" nil nil))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (let ((s (buffer-string)))
        (should (string-match-p "bash"     s))
        (should (string-match-p "fish"     s))
        (should (string-match-p "/bin/sh"  s))
        (should (string-match-p "running"  s))
        (should (string-match-p "detached" s))
        (should (string-match-p "dead"     s))))))

(ert-deftest kuro-lifecycle--list-sessions-uses-correct-buffer-name ()
  "kuro-list-sessions writes into the buffer named by kuro--buffer-name-sessions."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((0 "bash" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    ;; The sessions buffer must exist and carry the expected name.
    (should (get-buffer kuro--buffer-name-sessions))
    (should (string= (buffer-name (get-buffer kuro--buffer-name-sessions))
                     kuro--buffer-name-sessions))))

(ert-deftest kuro-lifecycle--list-sessions-point-at-min-after ()
  "kuro-list-sessions leaves point at the beginning of the sessions buffer."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((0 "bash" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (should (= (point) (point-min))))))

;;; ── Group 11: kuro-kill teardown ordering and kill-buffer ────────────────────
;;
;; Verifies that kuro-kill tears down in the correct sequence and that
;; kill-buffer is called on the current buffer at the end.

(ert-deftest kuro-lifecycle--kill-calls-kill-buffer-on-current ()
  "kuro-kill calls kill-buffer with the current buffer."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((killed-buf nil)
          (this-buf   (current-buffer)))
      (kuro-lifecycle-test--with-kill-stubs
        (cl-letf (((symbol-function 'kill-buffer)
                   (lambda (buf) (setq killed-buf buf))))
          (kuro-kill)
          (should (eq killed-buf this-buf)))))))

(ert-deftest kuro-lifecycle--kill-teardown-before-kill-buffer ()
  "kuro-kill calls kuro--teardown-session before kill-buffer."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((order nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)     (lambda ()      nil))
                ((symbol-function 'kuro--cleanup-render-state) (lambda ()      nil))
                ((symbol-function 'kuro--clear-all-image-overlays) (lambda ()  nil))
                ((symbol-function 'kuro--teardown-session)
                 (lambda () (push 'teardown order)))
                ((symbol-function 'kill-buffer)
                 (lambda (_buf) (push 'kill order))))
        (kuro-kill)
        (let ((seq (nreverse order)))
          (should (eq (nth 0 seq) 'teardown))
          (should (eq (nth 1 seq) 'kill)))))))

(ert-deftest kuro-lifecycle--kill-cleanup-before-teardown ()
  "kuro-kill calls kuro--cleanup-render-state before kuro--teardown-session."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((order nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)
                 (lambda () (push 'stop order)))
                ((symbol-function 'kuro--cleanup-render-state)
                 (lambda () (push 'cleanup order)))
                ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
                ((symbol-function 'kuro--teardown-session)
                 (lambda () (push 'teardown order)))
                ((symbol-function 'kill-buffer) (lambda (_buf) nil)))
        (kuro-kill)
        (let ((seq (nreverse order)))
          (should (equal (list 'stop 'cleanup 'teardown) seq)))))))

;;; ── Group 12: kuro--cleanup-render-state — image overlays and idempotency ────
;;
;; Covers kuro--clear-all-image-overlays being called and the idempotent
;; second-call behaviour.

(ert-deftest kuro-lifecycle--cleanup-render-state-calls-clear-image-overlays ()
  "kuro--cleanup-render-state always calls kuro--clear-all-image-overlays."
  (with-temp-buffer
    (let ((clear-called nil))
      (cl-letf (((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () (setq clear-called t))))
        (kuro--cleanup-render-state)
        (should clear-called)))))

(ert-deftest kuro-lifecycle--cleanup-render-state-idempotent ()
  "kuro--cleanup-render-state called twice leaves state at nil/0 with no error."
  (with-temp-buffer
    (setq-local kuro--tui-mode-active      t
                kuro--tui-mode-frame-count 3
                kuro--last-dirty-count     7
                kuro--mouse-mode           1
                kuro--mouse-sgr            t
                kuro--mouse-pixel-mode     t
                kuro--scroll-offset        5
                kuro--font-remap-cookie    nil)
    (cl-letf (((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil)))
      (kuro--cleanup-render-state)
      (kuro--cleanup-render-state)   ; second call — must not error
      (should-not kuro--tui-mode-active)
      (should (= kuro--mouse-mode 0))
      (should (= kuro--scroll-offset 0)))))


;;; Group 12 — kuro--def-control-key / kuro--clear-session-state structural tests

(ert-deftest kuro-lifecycle-def-control-key-expands-to-defun ()
  "`kuro--def-control-key' single-step expands to a `defun' form."
  (let ((exp (macroexpand-1
              '(kuro--def-control-key kuro-test--ck [?\C-c] "Test control key."))))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-test--ck))))

(ert-deftest kuro-lifecycle-def-control-key-expansion-has-interactive ()
  "`kuro--def-control-key' expansion contains `(interactive)' in the body."
  (let ((exp (macroexpand-1
              '(kuro--def-control-key kuro-test--ck2 [?\C-z] "doc"))))
    (should (member '(interactive) (cddr exp)))))

(ert-deftest kuro-lifecycle-clear-session-state-expands-to-setq ()
  "`kuro--clear-session-state' expands to a `setq' form resetting session identity."
  (let ((exp (macroexpand-1 '(kuro--clear-session-state))))
    (should (eq (car exp) 'setq))
    ;; The setq pairs must include kuro--initialized and kuro--session-id.
    (should (memq 'kuro--initialized exp))
    (should (memq 'kuro--session-id exp))))

(ert-deftest kuro-lifecycle-detach-and-clear-session-state-expands-to-condition-case ()
  "`kuro--detach-and-clear-session-state' expands to a detach guard and cleanup."
  (let ((exp (macroexpand-1 '(kuro--detach-and-clear-session-state 7))))
    (should
     (equal exp
            '(condition-case nil
                 (progn
                   (kuro-core-detach 7)
                   (kuro--clear-session-state))
               (error
                (kuro--clear-session-state)))))))

(provide 'kuro-lifecycle-test-2)

;;; kuro-lifecycle-test-2.el ends here
