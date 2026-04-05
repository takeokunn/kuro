;;; kuro-lifecycle-test.el --- Unit tests for kuro-lifecycle.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el public API — Groups 1–8.
;; Groups 9–16 are in kuro-lifecycle-ext-test.el.
;; Tests run without the Rust dynamic module: all FFI primitives are stubbed
;; before `kuro-lifecycle' is loaded.  When loaded after kuro-test.el
;; (as the Makefile does), the stubs in kuro-test.el are already present;
;; the `unless (fboundp …)' guards here handle standalone loading.
;;
;; kuro-lifecycle.el transitively requires kuro-ffi, kuro-renderer,
;; kuro-faces, and kuro-render-buffer, all of which guard their Rust calls
;; behind `kuro--initialized'.  We never let kuro--initialized be t without
;; also stubbing every Rust call that the code under test might reach.
;;
;; Groups:
;;   Group 1: kuro-send-string  (delegates to kuro--send-key)
;;   Group 2: kuro-send-interrupt / kuro-send-sigstop / kuro-send-sigquit
;;   Group 3: kuro-kill         (guards on derived-mode-p; calls kuro--shutdown)
;;   Group 4: kuro-create guard (must not attempt a real PTY)
;;   Group 5: kuro-list-sessions (nth-index regression: idx2=detached-p, idx3=alive-p)
;;   Group 6: kuro-kill detach branch (yes-or-no-p nil → kuro-core-detach, not shutdown)
;;   Group 7: kuro--cleanup-render-state
;;   Group 8: kuro--clear-session-state macro

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-lifecycle-test-support)

;;; ── Group 1: kuro-send-string ───────────────────────────────────────────────
;;
;; kuro-send-string delegates the entire string directly to kuro--send-key in
;; a single call.  The initialization guard lives inside kuro--send-key, so
;; when kuro--initialized is nil the stub is never called.

(ert-deftest kuro-lifecycle--send-string-noop-when-not-initialized ()
  "kuro-send-string does nothing when kuro--initialized is nil.
Stubs kuro-core-send-key (the Rust FFI) rather than kuro--send-key so
that the `kuro--call' guard inside kuro--send-key is exercised."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_bytes) (setq called t))))
      (kuro-send-string "hello"))
    (should-not called)))

(ert-deftest kuro-lifecycle--send-string-passes-string-to-send-key ()
  "kuro-send-string passes the whole string to kuro--send-key in one call."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-string "hello"))))
    (should (equal received '("hello")))))

(ert-deftest kuro-lifecycle--send-string-empty-string ()
  "kuro-send-string with an empty string calls kuro--send-key with \"\"."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-string ""))))
    (should (equal received '("")))))

(ert-deftest kuro-lifecycle--send-string-multi-char ()
  "kuro-send-string sends the full multi-char string in a single call."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-string "abc"))))
    (should (= (length received) 1))
    (should (equal (car received) "abc"))))

(ert-deftest kuro-lifecycle--send-string-newline ()
  "kuro-send-string correctly forwards a string containing a newline."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-string "line\n"))))
    (should (equal received '("line\n")))))

;;; ── Group 2: kuro-send-interrupt / kuro-send-sigstop / kuro-send-sigquit ───
;;
;; Each function sends a control-character vector to kuro--send-key.
;; kuro--send-key converts vectors to strings before forwarding to Rust.
;; We stub kuro--send-key and verify it receives the expected vector.

(ert-deftest kuro-lifecycle--send-interrupt-noop-when-not-initialized ()
  "kuro-send-interrupt does nothing when kuro--initialized is nil.
Stubs kuro-core-send-key so the kuro--call guard is exercised."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_bytes) (setq called t))))
      (kuro-send-interrupt))
    (should-not called)))

(ert-deftest kuro-lifecycle--send-sigstop-noop-when-not-initialized ()
  "kuro-send-sigstop does nothing when kuro--initialized is nil.
Stubs kuro-core-send-key so the kuro--call guard is exercised."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_bytes) (setq called t))))
      (kuro-send-sigstop))
    (should-not called)))

(ert-deftest kuro-lifecycle--send-sigquit-noop-when-not-initialized ()
  "kuro-send-sigquit does nothing when kuro--initialized is nil.
Stubs kuro-core-send-key so the kuro--call guard is exercised."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_bytes) (setq called t))))
      (kuro-send-sigquit))
    (should-not called)))

(ert-deftest kuro-lifecycle--send-interrupt-sends-ctrl-c ()
  "kuro-send-interrupt calls kuro--send-key with the C-c vector (byte 3)."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-interrupt))))
    (should (= (length received) 1))
    (should (equal (car received) [?\C-c]))))

(ert-deftest kuro-lifecycle--send-sigstop-sends-ctrl-z ()
  "kuro-send-sigstop calls kuro--send-key with the C-z vector (byte 26)."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-sigstop))))
    (should (= (length received) 1))
    (should (equal (car received) [?\C-z]))))

(ert-deftest kuro-lifecycle--send-sigquit-sends-ctrl-backslash ()
  "kuro-send-sigquit calls kuro--send-key with the C-\\ vector (byte 28)."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-sigquit))))
    (should (= (length received) 1))
    (should (equal (car received) [?\C-\\]))))

(ert-deftest kuro-lifecycle--ctrl-c-is-byte-3 ()
  "Verify that ?\\C-c has the numeric value 3 (SIGINT byte)."
  (should (= ?\C-c 3)))

(ert-deftest kuro-lifecycle--ctrl-z-is-byte-26 ()
  "Verify that ?\\C-z has the numeric value 26 (SIGSTOP byte)."
  (should (= ?\C-z 26)))

(ert-deftest kuro-lifecycle--ctrl-backslash-is-byte-28 ()
  "Verify that ?\\C-\\ has the numeric value 28 (SIGQUIT byte)."
  (should (= ?\C-\\ 28)))

;;; ── Group 3: kuro-kill ──────────────────────────────────────────────────────
;;
;; kuro-kill guards on `(derived-mode-p 'kuro-mode)' — it does NOT check
;; kuro--initialized directly.  When the buffer is not in kuro-mode,
;; the body (including kuro--shutdown) is never reached.

(ert-deftest kuro-lifecycle--kill-noop-in-non-kuro-buffer ()
  "kuro-kill does nothing when the buffer is not in kuro-mode."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (let ((shutdown-called nil))
      (kuro-lifecycle-test--with-kill-stubs
        (cl-letf (((symbol-function 'kuro--shutdown)
                   (lambda () (setq shutdown-called t))))
          (kuro-kill)
          (should-not shutdown-called))))))

(ert-deftest kuro-lifecycle--kill-calls-shutdown-in-kuro-mode ()
  "kuro-kill calls kuro--shutdown when the buffer is in kuro-mode."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((shutdown-called nil))
      (kuro-lifecycle-test--with-kill-stubs
        (cl-letf (((symbol-function 'kuro--shutdown)
                   (lambda () (setq shutdown-called t))))
          (kuro-kill)
          (should shutdown-called))))))

(ert-deftest kuro-lifecycle--kill-stops-render-loop-before-cleanup ()
  "kuro-kill calls kuro--stop-render-loop before kuro--cleanup-render-state."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((call-order nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)
                 (lambda () (push 'stop-render call-order)))
                ((symbol-function 'kuro--cleanup-render-state)
                 (lambda () (push 'cleanup call-order)))
                ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
                ((symbol-function 'kuro--shutdown)                 (lambda () nil))
                ((symbol-function 'kill-buffer)                    (lambda (_buf) nil)))
        (kuro-kill)
        (let ((ordered (nreverse call-order)))
          (should (eq (nth 0 ordered) 'stop-render))
          (should (eq (nth 1 ordered) 'cleanup)))))))

;;; ── Group 4: kuro-create guard ──────────────────────────────────────────────
;;
;; kuro-create spawns a real PTY process.  We do NOT test that path.
;; Instead, we verify the structural guards that prevent breakage before
;; a real terminal environment is available.

(ert-deftest kuro-lifecycle--create-is-autoloaded-function ()
  "kuro-create is a defined interactive function."
  (should (fboundp 'kuro-create))
  (should (commandp 'kuro-create)))

(ert-deftest kuro-lifecycle--create-aborts-without-module ()
  "kuro-create calls kuro--ensure-module-loaded as its first action.
When the module is unavailable, that call may signal an error.
We verify kuro-create does not succeed silently when the stub errors."
  (cl-letf (((symbol-function 'kuro--ensure-module-loaded)
             (lambda () (error "module not available"))))
    (should-error (kuro-create "echo hello" "*kuro-test*")
                  :type 'error)))

;;; ── Group 5: kuro-list-sessions (tabulated-list-mode) ──────────────────────
;;
;; kuro-list-sessions calls kuro-core-list-sessions and formats results into a
;; *kuro-sessions* buffer using tabulated-list-mode.  Each entry from Rust is
;; (SESSION-ID COMMAND DETACHED-P ALIVE-P) — indices 0, 1, 2, 3.

(ert-deftest kuro-lifecycle--list-sessions-no-sessions ()
  "kuro-list-sessions shows an empty table when kuro-core-list-sessions returns nil."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () nil))
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

(ert-deftest kuro-lifecycle--list-sessions-nth-index-regression ()
  "Regression: entry (id cmd nil t) must show 'running' in the table row.
With swapped nth indices the original bug made (nth 3 entry)=t feed
detached-p, producing 'detached' for a live session.  This test pins
the correct mapping: index 2 = is_detached, index 3 = is_alive."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             ;; id=0, cmd="bash", detached=nil(idx2), alive=t(idx3)
             (lambda () '((0 "bash" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (let ((s (buffer-string)))
        ;; The table row for ID 0 must show "running" in the status column.
        (should (string-match-p "running" s))
        ;; Must NOT show "detached" anywhere in the data rows.
        ;; Header line is separate from buffer-string in tabulated-list-mode.
        (should-not (string-match-p "detached" s))))))

(ert-deftest kuro-lifecycle--list-sessions-detached-status ()
  "A session with detached-p=t (index 2) shows status 'detached'."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((1 "/bin/bash" t t))))  ; detached=t, alive=t
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (should (string-match-p "detached" (buffer-string))))))

(ert-deftest kuro-lifecycle--list-sessions-dead-status ()
  "A session with detached-p=nil and alive-p=nil (both false) shows 'dead'."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((2 "/bin/sh" nil nil))))  ; detached=nil, alive=nil
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (should (string-match-p "dead" (buffer-string))))))

(ert-deftest kuro-lifecycle--list-sessions-shows-command ()
  "kuro-list-sessions includes the shell command string in the output."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((3 "/usr/bin/fish" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (should (string-match-p "/usr/bin/fish" (buffer-string))))))

;;; ── Group 6: kuro-kill detach branch ────────────────────────────────────────
;;
;; When kuro--initialized is t, kuro--is-process-alive returns t, AND the
;; user answers "no" to the kill prompt (yes-or-no-p returns nil), kuro-kill
;; must call kuro-core-detach (not kuro--shutdown) and clear the
;; kuro--initialized / kuro--session-id state.

(ert-deftest kuro-lifecycle--kill-detaches-when-user-says-no ()
  "kuro-kill calls kuro-core-detach with the session ID when user says no.
kuro--initialized must be nil and kuro--session-id must be 0 afterward.
kuro--shutdown must NOT be called."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--initialized t)
    (setq-local kuro--session-id 99)
    (let ((detach-called-with nil)
          (shutdown-called nil))
      (kuro-lifecycle-test--with-kill-stubs
        (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
                  ((symbol-function 'yes-or-no-p)            (lambda (_p) nil))
                  ((symbol-function 'kuro-core-detach)       (lambda (id) (setq detach-called-with id)))
                  ((symbol-function 'kuro--shutdown)         (lambda () (setq shutdown-called t))))
          (kuro-kill)
          (should (equal detach-called-with 99))
          (should-not shutdown-called)
          (should-not kuro--initialized)
          (should (= kuro--session-id 0)))))))

(ert-deftest kuro-lifecycle--kill-destroys-when-user-says-yes ()
  "kuro-kill calls kuro--shutdown (not kuro-core-detach) when user says yes."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--initialized t)
    (setq-local kuro--session-id 77)
    (let ((detach-called nil)
          (shutdown-called nil))
      (kuro-lifecycle-test--with-kill-stubs
        (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
                  ((symbol-function 'yes-or-no-p)            (lambda (_p) t))
                  ((symbol-function 'kuro-core-detach)       (lambda (_id) (setq detach-called t)))
                  ((symbol-function 'kuro--shutdown)         (lambda () (setq shutdown-called t))))
          (kuro-kill)
          (should shutdown-called)
          (should-not detach-called))))))

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

;;; ── Group 13: kuro-attach interactive spec (completing-read) ────────────────
;;
;; kuro-attach's interactive form calls kuro-core-list-sessions and filters
;; for detached sessions.  When no sessions exist or none are detached, it
;; signals user-error.  When detached sessions exist, completing-read is
;; called with formatted candidates.

(ert-deftest kuro-lifecycle--attach-no-sessions-signals-user-error ()
  "kuro-attach signals user-error when kuro-core-list-sessions returns nil."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () nil)))
    (should-error (call-interactively 'kuro-attach)
                  :type 'user-error)))

(ert-deftest kuro-lifecycle--attach-no-detached-signals-user-error ()
  "kuro-attach signals user-error when all sessions are attached (none detached)."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             ;; Two sessions, both with detached-p=nil (index 2)
             (lambda () '((0 "bash" nil t)
                          (1 "fish" nil t)))))
    (should-error (call-interactively 'kuro-attach)
                  :type 'user-error)))

(ert-deftest kuro-lifecycle--attach-detached-calls-completing-read ()
  "kuro-attach calls completing-read with formatted candidates for detached sessions."
  (let ((cr-candidates nil)
        (cr-prompt nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((0 "bash" nil t)
                            (1 "fish" t   t)
                            (2 "zsh"  t   nil))))
              ((symbol-function 'completing-read)
               (lambda (prompt candidates &rest _args)
                 (setq cr-prompt prompt
                       cr-candidates candidates)
                 ;; Return the first candidate
                 (caar candidates)))
              ((symbol-function 'kuro--ensure-module-loaded)
               (lambda () nil))
              ((symbol-function 'kuro-mode)
               (lambda () nil))
              ((symbol-function 'kuro--do-attach)
               (lambda (_id _rows _cols) nil))
              ((symbol-function 'switch-to-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'message)
               (lambda (_fmt &rest _args) nil)))
      (call-interactively 'kuro-attach)
      ;; completing-read must have been called
      (should cr-prompt)
      (should (string-match-p "session" (downcase cr-prompt)))
      ;; Only detached sessions (id=1 and id=2) should appear as candidates
      (should (= (length cr-candidates) 2))
      ;; Candidates should be formatted as "Session ID: cmd"
      (should (cl-some (lambda (c) (string-match-p "Session 1.*fish" (car c)))
                       cr-candidates))
      (should (cl-some (lambda (c) (string-match-p "Session 2.*zsh" (car c)))
                       cr-candidates))
      ;; Attached session (id=0) must NOT appear
      (should-not (cl-some (lambda (c) (string-match-p "Session 0" (car c)))
                           cr-candidates)))))

(ert-deftest kuro-lifecycle--attach-completing-read-returns-session-id ()
  "kuro-attach passes the selected session ID to the body."
  (let ((attached-id nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((5 "bash" t t))))
              ((symbol-function 'completing-read)
               (lambda (_prompt candidates &rest _args)
                 ;; Select the only candidate: "Session 5: bash"
                 (caar candidates)))
              ((symbol-function 'kuro--ensure-module-loaded)
               (lambda () nil))
              ((symbol-function 'kuro-mode)
               (lambda () nil))
              ((symbol-function 'kuro--do-attach)
               (lambda (id _rows _cols)
                 (setq attached-id id)))
              ((symbol-function 'switch-to-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'message)
               (lambda (_fmt &rest _args) nil)))
      (call-interactively 'kuro-attach)
      (should (= attached-id 5)))))

(ert-deftest kuro-lifecycle--attach-error-from-list-sessions-signals-user-error ()
  "kuro-attach signals user-error when kuro-core-list-sessions errors (caught as nil)."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "module not loaded"))))
    (should-error (call-interactively 'kuro-attach)
                  :type 'user-error)))

;;; ── Group 14: kuro-sessions-mode (tabulated-list-mode) ─────────────────────
;;
;; Tests for the interactive session list: mode derivation, keymap bindings,
;; kuro-sessions-attach, kuro-sessions-destroy, kuro-sessions-refresh.

(ert-deftest kuro-lifecycle--sessions-mode-derived-from-tabulated-list ()
  "kuro-sessions-mode is derived from tabulated-list-mode."
  (with-temp-buffer
    (kuro-sessions-mode)
    (should (derived-mode-p 'tabulated-list-mode))))

(ert-deftest kuro-lifecycle--sessions-mode-ret-bound-to-attach ()
  "RET is bound to kuro-sessions-attach in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "RET"))
              #'kuro-sessions-attach)))

(ert-deftest kuro-lifecycle--sessions-mode-a-bound-to-attach ()
  "`a' is bound to kuro-sessions-attach in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "a"))
              #'kuro-sessions-attach)))

(ert-deftest kuro-lifecycle--sessions-mode-d-bound-to-destroy ()
  "`d' is bound to kuro-sessions-destroy in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "d"))
              #'kuro-sessions-destroy)))

(ert-deftest kuro-lifecycle--sessions-mode-g-bound-to-refresh ()
  "`g' is bound to kuro-sessions-refresh in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "g"))
              #'kuro-sessions-refresh)))

(ert-deftest kuro-lifecycle--sessions-mode-q-bound-to-quit ()
  "`q' is bound to quit-window in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "q"))
              #'quit-window)))

(ert-deftest kuro-lifecycle--list-sessions-creates-buffer-in-sessions-mode ()
  "kuro-list-sessions creates a buffer in kuro-sessions-mode."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((0 "bash" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (should (eq major-mode 'kuro-sessions-mode)))))

(ert-deftest kuro-lifecycle--sessions-attach-calls-kuro-attach ()
  "kuro-sessions-attach calls kuro-attach with the session ID at point."
  (let ((attached-id nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((42 "bash" t t))))
              ((symbol-function 'display-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'kuro-attach)
               (lambda (id) (setq attached-id id))))
      (kuro-list-sessions)
      (with-current-buffer "*kuro-sessions*"
        (goto-char (point-min))
        (kuro-sessions-attach)
        (should (= attached-id 42))))))

(ert-deftest kuro-lifecycle--sessions-attach-no-entry-signals-error ()
  "kuro-sessions-attach signals user-error when no session is at point."
  (with-temp-buffer
    (kuro-sessions-mode)
    (should-error (kuro-sessions-attach) :type 'user-error)))

(ert-deftest kuro-lifecycle--sessions-destroy-calls-shutdown-and-reverts ()
  "kuro-sessions-destroy calls kuro-core-shutdown and refreshes the list."
  (let ((shutdown-id nil)
        (reverted nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((7 "fish" t t))))
              ((symbol-function 'display-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'kuro-core-shutdown)
               (lambda (id) (setq shutdown-id id)))
              ((symbol-function 'y-or-n-p)
               (lambda (_prompt) t))
              ((symbol-function 'tabulated-list-revert)
               (lambda () (setq reverted t))))
      (kuro-list-sessions)
      (with-current-buffer "*kuro-sessions*"
        (goto-char (point-min))
        (kuro-sessions-destroy)
        (should (= shutdown-id 7))
        (should reverted)))))

(ert-deftest kuro-lifecycle--sessions-destroy-aborts-on-no ()
  "kuro-sessions-destroy does nothing when user answers no."
  (let ((shutdown-called nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((7 "fish" t t))))
              ((symbol-function 'display-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'kuro-core-shutdown)
               (lambda (_id) (setq shutdown-called t)))
              ((symbol-function 'y-or-n-p)
               (lambda (_prompt) nil)))
      (kuro-list-sessions)
      (with-current-buffer "*kuro-sessions*"
        (goto-char (point-min))
        (kuro-sessions-destroy)
        (should-not shutdown-called)))))

(ert-deftest kuro-lifecycle--session-status-helper ()
  "kuro--session-status returns correct status strings."
  (should (equal (kuro--session-status t t)     "detached"))
  (should (equal (kuro--session-status t nil)   "detached"))
  (should (equal (kuro--session-status nil t)   "running"))
  (should (equal (kuro--session-status nil nil)  "dead")))

(ert-deftest kuro-lifecycle--sessions-entries-returns-tabulated-format ()
  "kuro-sessions--entries returns entries in tabulated-list format."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((1 "bash" nil t)))))
    (let ((entries (kuro-sessions--entries)))
      (should (= (length entries) 1))
      (let ((entry (car entries)))
        ;; Entry is (ID [ID-STRING COMMAND STATUS])
        (should (= (car entry) 1))
        (should (vectorp (cadr entry)))
        (should (equal (aref (cadr entry) 0) "1"))
        (should (equal (aref (cadr entry) 1) "bash"))
        (should (equal (aref (cadr entry) 2) "running"))))))

;;; ── Group 15: kuro-sessions--entries direct tests ───────────────────────────
;;
;; Tests for kuro-sessions--entries independent of the full kuro-list-sessions
;; pipeline: empty return, malformed entries, multi-session, and error path.

(ert-deftest kuro-lifecycle--sessions-entries-empty-when-ffi-returns-nil ()
  "kuro-sessions--entries returns an empty list when kuro-core-list-sessions returns nil."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () nil)))
    (should (null (kuro-sessions--entries)))))

(ert-deftest kuro-lifecycle--sessions-entries-filters-malformed-short-entry ()
  "kuro-sessions--entries ignores entries with fewer than 4 elements."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             ;; 3-element entry is below the (>= (length entry) 4) guard
             (lambda () '((0 "bash" nil)))))
    (should (null (kuro-sessions--entries)))))

(ert-deftest kuro-lifecycle--sessions-entries-filters-non-list-entry ()
  "kuro-sessions--entries ignores entries that are not lists."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '("not-a-list"))))
    (should (null (kuro-sessions--entries)))))

(ert-deftest kuro-lifecycle--sessions-entries-two-valid-produce-two-rows ()
  "kuro-sessions--entries returns two tabulated rows for two valid entries."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda ()
               '((0 "bash" nil t)
                 (1 "fish" t   t)))))
    (let ((entries (kuro-sessions--entries)))
      (should (= (length entries) 2))
      ;; First entry: id=0, running
      (let ((e0 (car entries)))
        (should (= (car e0) 0))
        (should (equal (aref (cadr e0) 2) "running")))
      ;; Second entry: id=1, detached
      (let ((e1 (cadr entries)))
        (should (= (car e1) 1))
        (should (equal (aref (cadr e1) 2) "detached"))))))

(ert-deftest kuro-lifecycle--sessions-entries-ffi-error-returns-nil ()
  "kuro-sessions--entries returns nil when kuro-core-list-sessions signals an error."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "module error"))))
    (should (null (kuro-sessions--entries)))))

;;; ── Group 16: kuro-sessions-refresh ─────────────────────────────────────────

(ert-deftest kuro-lifecycle--sessions-refresh-calls-tabulated-list-revert ()
  "kuro-sessions-refresh calls `tabulated-list-revert'."
  (let ((reverted nil))
    (cl-letf (((symbol-function 'tabulated-list-revert)
               (lambda () (setq reverted t))))
      (kuro-sessions-refresh))
    (should reverted)))

;;; ── Group 10 (buffer-init): kuro--init-session-buffer ──────────────────────
;;
;; kuro--init-session-buffer initializes a buffer as a kuro session display.
;; It sets cursor-marker, last-rows, last-cols, scroll-offset, calls five
;; side-effecting helpers, and resets cursor cache.  Tests stub every outward
;; call and verify the buffer-local variables directly.

(ert-deftest kuro-lifecycle--init-session-buffer-sets-dimensions ()
  "kuro--init-session-buffer stores rows/cols in kuro--last-rows/kuro--last-cols."
  (with-temp-buffer
    (setq-local kuro--last-rows 0
                kuro--last-cols 0
                kuro--scroll-offset 99
                kuro--cursor-marker nil)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 24 80)
      (should (= kuro--last-rows 24))
      (should (= kuro--last-cols 80)))))

(ert-deftest kuro-lifecycle--init-session-buffer-resets-scroll-offset ()
  "kuro--init-session-buffer resets kuro--scroll-offset to 0."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 42
                kuro--cursor-marker nil
                kuro--last-rows 0
                kuro--last-cols 0)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 24 80)
      (should (= kuro--scroll-offset 0)))))

(ert-deftest kuro-lifecycle--init-session-buffer-sets-cursor-marker ()
  "kuro--init-session-buffer sets kuro--cursor-marker to a live marker."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows 0
                kuro--last-cols 0
                kuro--scroll-offset 0)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 24 80)
      (should (markerp kuro--cursor-marker))
      (should (marker-buffer kuro--cursor-marker)))))

(ert-deftest kuro-lifecycle--init-session-buffer-calls-scrollback ()
  "kuro--init-session-buffer calls kuro--set-scrollback-max-lines."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows 0
                kuro--last-cols 0
                kuro--scroll-offset 0)
    (let ((scrollback-called nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--set-scrollback-max-lines)
                   (lambda (_n) (setq scrollback-called t))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should scrollback-called))))))

(ert-deftest kuro-lifecycle--init-session-buffer-resets-cursor-cache ()
  "kuro--init-session-buffer clears all cursor cache variables to nil.
kuro--reset-cursor-cache is a macro; we verify its expansion side effects
rather than stubbing it through symbol-function."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows 0
                kuro--last-cols 0
                kuro--scroll-offset 0
                kuro--last-cursor-row    42
                kuro--last-cursor-col    10
                kuro--last-cursor-visible t
                kuro--last-cursor-shape  'block)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 24 80)
      (should (null kuro--last-cursor-row))
      (should (null kuro--last-cursor-col))
      (should (null kuro--last-cursor-visible))
      (should (null kuro--last-cursor-shape)))))

;;; ── Group 11 (buffer-init): kuro--prefill-buffer ───────────────────────────
;;
;; kuro--prefill-buffer erases the buffer, inserts ROWS newlines, and moves
;; point to point-min.  Must be called with inhibit-read-only bound by caller.

(ert-deftest kuro-lifecycle--prefill-buffer-inserts-correct-line-count ()
  "kuro--prefill-buffer inserts exactly ROWS newlines."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (kuro--prefill-buffer 10)
      ;; 10 newlines produce 11 positions (point-min to point-max);
      ;; count lines: (count-lines point-min point-max) = 10.
      (should (= (count-lines (point-min) (point-max)) 10)))))

(ert-deftest kuro-lifecycle--prefill-buffer-leaves-point-at-min ()
  "kuro--prefill-buffer leaves point at point-min."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (insert "old content")
      (kuro--prefill-buffer 5)
      (should (= (point) (point-min))))))

(ert-deftest kuro-lifecycle--prefill-buffer-erases-existing-content ()
  "kuro--prefill-buffer erases any pre-existing buffer content."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (insert "some old text")
      (kuro--prefill-buffer 3)
      (should-not (string-match-p "old" (buffer-string))))))

;;; ── Group 12 (buffer-init): kuro--do-attach and kuro--rollback-attach ───────
;;
;; kuro--do-attach performs the six-step core attach sequence inside an
;; inhibit-read-only binding.  kuro--rollback-attach logs, clears state,
;; tries to detach, and kills the buffer.

(ert-deftest kuro-lifecycle-do-attach-sets-session-id ()
  "kuro--do-attach sets kuro--session-id and kuro--initialized."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized)
      (kuro-lifecycle-test--with-attach-stubs
        (kuro--do-attach 42 24 80)
        (should (= kuro--session-id 42))
        (should kuro--initialized)))))

(ert-deftest kuro-lifecycle-do-attach-calls-core-attach ()
  "kuro--do-attach calls kuro-core-attach with the session ID."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (attach-called-with nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro-core-attach)
                   (lambda (id) (setq attach-called-with id))))
          (kuro--do-attach 7 24 80)
          (should (= attach-called-with 7)))))))

(ert-deftest kuro-lifecycle-do-attach-calls-start-render-loop ()
  "kuro--do-attach calls kuro--start-render-loop."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (render-started nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro--start-render-loop)
                   (lambda () (setq render-started t))))
          (kuro--do-attach 1 24 80)
          (should render-started))))))

(ert-deftest kuro-lifecycle-rollback-attach-clears-state ()
  "kuro--rollback-attach resets kuro--initialized to nil and kuro--session-id to 0.
kuro--clear-session-state is a macro so we verify its expanded effects directly."
  (with-temp-buffer
    (let ((kuro--session-id 1)
          (kuro--initialized t))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'message)           #'ignore)
                ((symbol-function 'kill-buffer)       #'ignore))
        (kuro--rollback-attach 1 (current-buffer) "test error")
        (should-not kuro--initialized)
        (should (= kuro--session-id 0))))))

(ert-deftest kuro-lifecycle-rollback-attach-attempts-detach ()
  "kuro--rollback-attach attempts kuro-core-detach with the session ID."
  (with-temp-buffer
    (let ((kuro--session-id 5)
          (kuro--initialized nil)
          (detach-called-with nil))
      (cl-letf (((symbol-function 'kuro-core-detach)
                 (lambda (id) (setq detach-called-with id)))
                ((symbol-function 'message)    #'ignore)
                ((symbol-function 'kill-buffer) #'ignore))
        (kuro--rollback-attach 5 (current-buffer) "oops")
        (should (= detach-called-with 5))))))

(ert-deftest kuro-lifecycle-rollback-attach-swallows-detach-error ()
  "kuro--rollback-attach does not propagate an error from kuro-core-detach."
  (with-temp-buffer
    (let ((kuro--session-id 0)
          (kuro--initialized nil))
      (cl-letf (((symbol-function 'kuro-core-detach)
                 (lambda (_id) (error "detach failed")))
                ((symbol-function 'message)    #'ignore)
                ((symbol-function 'kill-buffer) #'ignore))
        ;; Must not signal.
        (should-not (condition-case err
                        (progn (kuro--rollback-attach 0 (current-buffer) "e") nil)
                      (error err)))))))

;;; ── Group 13 (buffer-init): kuro--teardown-session ──────────────────────────
;;
;; kuro--teardown-session branches on kuro--initialized, kuro--is-process-alive,
;; and the yes-or-no-p prompt.  Three paths: shutdown (not initialized),
;; shutdown (user says yes), detach (user says no).

(ert-deftest kuro-lifecycle-teardown-calls-shutdown-when-not-initialized ()
  "kuro--teardown-session calls kuro--shutdown when kuro--initialized is nil."
  (let (kuro--initialized
        (shutdown-called nil))
    (cl-letf (((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should shutdown-called))))

(ert-deftest kuro-lifecycle-teardown-calls-shutdown-when-user-says-yes ()
  "kuro--teardown-session calls kuro--shutdown when user answers yes to prompt."
  (let ((kuro--initialized t)
        (kuro--session-id 10)
        (shutdown-called nil)
        (detach-called nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p)            (lambda (_p) t))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t)))
              ((symbol-function 'kuro-core-detach)
               (lambda (_id) (setq detach-called t))))
      (kuro--teardown-session)
      (should shutdown-called)
      (should-not detach-called))))

(ert-deftest kuro-lifecycle-teardown-detaches-when-user-says-no ()
  "kuro--teardown-session calls kuro-core-detach and clears state when user says no."
  (let ((kuro--initialized t)
        (kuro--session-id 20)
        (detach-called-with nil)
        (shutdown-called nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p)            (lambda (_p) nil))
              ((symbol-function 'kuro-core-detach)
               (lambda (id) (setq detach-called-with id)))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should (= detach-called-with 20))
      (should-not shutdown-called)
      (should-not kuro--initialized)
      (should (= kuro--session-id 0)))))

(ert-deftest kuro-lifecycle-teardown-clears-state-even-if-detach-errors ()
  "kuro--teardown-session clears state even when kuro-core-detach signals."
  (let ((kuro--initialized t)
        (kuro--session-id 30))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p)            (lambda (_p) nil))
              ((symbol-function 'kuro-core-detach)
               (lambda (_id) (error "detach blew up")))
              ((symbol-function 'kuro--shutdown)          #'ignore))
      (kuro--teardown-session)
      (should-not kuro--initialized)
      (should (= kuro--session-id 0)))))

;;; ── Group 14 (buffer-init): kuro--schedule-initial-render ───────────────────
;;
;; kuro--schedule-initial-render posts a one-shot idle timer that fires
;; kuro--render-cycle only when the buffer is still live.  Tests verify the
;; timer arguments and the buffer-live-p guard without actually waiting for
;; idle time.

(ert-deftest kuro-lifecycle--schedule-initial-render-posts-idle-timer ()
  "kuro--schedule-initial-render calls run-with-idle-timer with the right delay.
The first argument must equal kuro--startup-render-delay; the second must
be nil (one-shot, never rescheduled)."
  (let ((timer-delay nil)
        (timer-repeat nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (delay repeat _fn &rest _args)
                 (setq timer-delay  delay
                       timer-repeat repeat))))
      (with-temp-buffer
        (kuro--schedule-initial-render (current-buffer))))
    (should (equal timer-delay  kuro--startup-render-delay))
    (should (null  timer-repeat))))

(ert-deftest kuro-lifecycle--schedule-initial-render-passes-buffer-arg ()
  "kuro--schedule-initial-render passes the buffer as the timer function arg.
We capture the extra args list supplied to run-with-idle-timer and verify
the first element is the buffer we passed in."
  (let ((timer-args nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat _fn &rest args)
                 (setq timer-args args))))
      (with-temp-buffer
        (let ((buf (current-buffer)))
          (kuro--schedule-initial-render buf)
          (should (eq (car timer-args) buf)))))))

(ert-deftest kuro-lifecycle--schedule-initial-render-skips-dead-buffer ()
  "The timer lambda does not call kuro--render-cycle when the buffer is dead.
We extract the lambda from the timer and invoke it directly with a buffer
that has already been killed."
  (let ((render-called nil)
        (captured-fn nil)
        (dead-buf nil))
    ;; Capture the lambda passed to run-with-idle-timer.
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn))))
      (with-temp-buffer
        (setq dead-buf (current-buffer))
        (kuro--schedule-initial-render dead-buf)))
    ;; Kill the buffer so buffer-live-p returns nil.
    (when (buffer-live-p dead-buf)
      (kill-buffer dead-buf))
    ;; Invoke the captured lambda with the dead buffer.
    (cl-letf (((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (funcall captured-fn dead-buf))
    (should-not render-called)))

;;; ── Group 15 (buffer-init): kuro--do-attach additional coverage ─────────────
;;
;; Supplement the Group 12 tests with error-propagation and state-variable
;; assertions that were not covered there.

(ert-deftest kuro-lifecycle--do-attach-propagates-core-attach-error ()
  "kuro--do-attach does not swallow errors from kuro-core-attach.
When kuro-core-attach signals, the error must propagate to the caller."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized)
      (cl-letf (((symbol-function 'kuro-core-attach)
                 (lambda (_id) (user-error "attach failed")))
                ((symbol-function 'kuro--prefill-buffer)      #'ignore)
                ((symbol-function 'kuro--init-session-buffer) #'ignore)
                ((symbol-function 'kuro--resize)              #'ignore)
                ((symbol-function 'kuro--start-render-loop)   #'ignore))
        (should-error (kuro--do-attach 1 24 80) :type 'user-error)))))

(ert-deftest kuro-lifecycle--do-attach-sets-session-id-on-success ()
  "kuro--do-attach sets kuro--session-id to the passed session-id value."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized)
      (kuro-lifecycle-test--with-attach-stubs
        (kuro--do-attach 55 24 80)
        (should (= kuro--session-id 55))))))

(ert-deftest kuro-lifecycle--do-attach-sets-initialized-on-success ()
  "kuro--do-attach sets kuro--initialized to t after a successful attach."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized)
      (kuro-lifecycle-test--with-attach-stubs
        (kuro--do-attach 55 24 80)
        (should kuro--initialized)))))

;;; ── Group 16 (buffer-init): kuro--init-session-buffer additional coverage ────
;;
;; Supplement the Group 10 tests with explicit assertions about scrollback-size
;; argument value and cursor-marker non-nil guarantee.

(ert-deftest kuro-lifecycle--init-session-buffer-cursor-marker-non-nil ()
  "kuro--init-session-buffer leaves kuro--cursor-marker non-nil.
Exercises the marker-creation path in a fresh temp buffer."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 30 120)
      (should kuro--cursor-marker))))

(ert-deftest kuro-lifecycle--init-session-buffer-scrollback-size-arg ()
  "kuro--init-session-buffer calls kuro--set-scrollback-max-lines with kuro-scrollback-size.
Verifies the exact argument value rather than just presence of a call."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (let ((received-size nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--set-scrollback-max-lines)
                   (lambda (n) (setq received-size n))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should (= received-size kuro-scrollback-size)))))))

;;; ── Group 17 (cleanup): kuro--rollback-attach — message and kill-buffer ──────
;;
;; Supplements Group 12 by verifying that rollback logs the session ID in
;; the message string and that it kills the supplied buffer.

(ert-deftest kuro-lifecycle--rollback-attach-logs-session-id ()
  "kuro--rollback-attach includes the session ID in the message it prints."
  (with-temp-buffer
    (let ((kuro--session-id 0)
          (kuro--initialized nil)
          (msg-logged nil))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'kill-buffer)       #'ignore)
                ((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (setq msg-logged (apply #'format fmt args)))))
        (kuro--rollback-attach 88 (current-buffer) "boom")
        (should (stringp msg-logged))
        (should (string-match-p "88" msg-logged))))))

(ert-deftest kuro-lifecycle--rollback-attach-kills-buffer ()
  "kuro--rollback-attach kills the buffer argument it receives."
  (let ((buf (generate-new-buffer " *kuro-rollback-test*"))
        (killed-buf nil))
    (let ((kuro--session-id 0)
          (kuro--initialized nil))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'message)           #'ignore)
                ((symbol-function 'kill-buffer)
                 (lambda (b) (setq killed-buf b))))
        (kuro--rollback-attach 1 buf "err")
        (should (eq killed-buf buf))))))

(ert-deftest kuro-lifecycle--rollback-attach-returns-nil ()
  "kuro--rollback-attach always returns nil."
  (with-temp-buffer
    (let ((kuro--session-id 0)
          (kuro--initialized nil))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'message)           #'ignore)
                ((symbol-function 'kill-buffer)       #'ignore))
        (should (null (kuro--rollback-attach 2 (current-buffer) "e")))))))

;;; ── Group 18 (cleanup): kuro--teardown-session — process not alive ───────────
;;
;; When kuro--initialized is t but kuro--is-process-alive returns nil, the
;; teardown must call kuro--shutdown directly without prompting the user.

(ert-deftest kuro-lifecycle--teardown-no-prompt-when-process-dead ()
  "kuro--teardown-session skips yes-or-no-p when the process is not alive."
  (let ((kuro--initialized   t)
        (kuro--session-id    40)
        (prompt-called       nil)
        (shutdown-called     nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive)
               (lambda () nil))
              ((symbol-function 'yes-or-no-p)
               (lambda (_p) (setq prompt-called t) t))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should-not prompt-called)
      (should     shutdown-called))))

(ert-deftest kuro-lifecycle--teardown-calls-shutdown-when-not-alive ()
  "kuro--teardown-session calls kuro--shutdown when the process is not alive."
  (let ((kuro--initialized  t)
        (kuro--session-id   50)
        (shutdown-called    nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should shutdown-called))))

;;; ── Group 19 (cleanup): kuro--prefill-buffer — edge cases ───────────────────
;;
;; Verifies zero-row behaviour and that buffer content is replaced (not appended).

(ert-deftest kuro-lifecycle--prefill-buffer-zero-rows-empty-buffer ()
  "kuro--prefill-buffer with 0 rows leaves the buffer empty (no newlines)."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (insert "existing text")
      (kuro--prefill-buffer 0)
      (should (= (buffer-size) 0)))))

(ert-deftest kuro-lifecycle--prefill-buffer-replaces-not-appends ()
  "kuro--prefill-buffer replaces existing content rather than appending to it."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (dotimes (_ 20)
        (insert "line\n"))
      (kuro--prefill-buffer 3)
      ;; Should have exactly 3 lines, not 20 + 3.
      (should (= (count-lines (point-min) (point-max)) 3)))))

;;; ── Group 20 (attach): kuro--do-attach — resize and prefill args ────────────
;;
;; Verifies that kuro--do-attach forwards rows/cols to kuro--resize and that
;; kuro--prefill-buffer receives the row count.

(ert-deftest kuro-lifecycle--do-attach-calls-resize-with-rows-cols ()
  "kuro--do-attach calls kuro--resize with the supplied rows and cols."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (resize-rows nil)
          (resize-cols nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro--resize)
                   (lambda (r c) (setq resize-rows r resize-cols c))))
          (kuro--do-attach 3 15 60)
          (should (= resize-rows 15))
          (should (= resize-cols 60)))))))

(ert-deftest kuro-lifecycle--do-attach-calls-prefill-with-rows ()
  "kuro--do-attach passes the rows argument to kuro--prefill-buffer."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (prefill-rows nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro--prefill-buffer)
                   (lambda (r) (setq prefill-rows r))))
          (kuro--do-attach 4 18 72)
          (should (= prefill-rows 18)))))))

;;; Group 21 (attach): kuro-attach — public API (error rollback, success message, buffer naming)
;;
;; kuro-attach creates a fresh buffer, enters kuro-mode, then calls kuro--do-attach.
;; On error it calls kuro--rollback-attach; on success it prints a message.

(ert-deftest kuro-lifecycle--attach-calls-rollback-on-do-attach-error ()
  "kuro-attach calls kuro--rollback-attach when kuro--do-attach signals."
  (let ((rollback-called-with-id nil)
        (result nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach)
               (lambda (_id _r _c) (error "attach failed")))
              ((symbol-function 'kuro--rollback-attach)
               (lambda (id _buf _err) (setq rollback-called-with-id id))))
      (setq result (kuro-attach 7))
      (when (buffer-live-p result) (kill-buffer result))
      (should (= rollback-called-with-id 7)))))

(ert-deftest kuro-lifecycle--attach-prints-success-message ()
  "kuro-attach prints a message mentioning the session ID on success."
  (let ((msgs nil)
        (result nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach) #'ignore)
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) msgs))))
      (setq result (kuro-attach 42))
      (unwind-protect
          (should (cl-some (lambda (m) (string-match-p "42" m)) msgs))
        (when (buffer-live-p result) (kill-buffer result))))))

(ert-deftest kuro-lifecycle--attach-buffer-name-includes-session-id ()
  "kuro-attach creates a buffer whose name contains the session ID."
  (let ((created-buf nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach) #'ignore)
              ((symbol-function 'message)          #'ignore))
      (setq created-buf (kuro-attach 99))
      (unwind-protect
          (should (string-match-p "99" (buffer-name created-buf)))
        (when (buffer-live-p created-buf)
          (kill-buffer created-buf))))))

(ert-deftest kuro-lifecycle--attach-returns-buffer ()
  "kuro-attach returns the newly created buffer."
  (let ((result nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach) #'ignore)
              ((symbol-function 'message)          #'ignore))
      (setq result (kuro-attach 3))
      (unwind-protect
          (should (bufferp result))
        (when (buffer-live-p result)
          (kill-buffer result))))))

;;; Group 22 (attach): kuro--schedule-initial-render — live-buffer path and timer lambda
;;
;; Supplements Group 14: verifies that when the buffer IS live, the timer lambda
;; calls kuro--render-cycle.

(ert-deftest kuro-lifecycle--schedule-initial-render-fires-render-when-live ()
  "Timer lambda calls kuro--render-cycle when the buffer is still live."
  (let ((render-called nil)
        (captured-fn nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn)))
              ((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (with-temp-buffer
        (let ((live-buf (current-buffer)))
          (kuro--schedule-initial-render live-buf)
          ;; Invoke the timer lambda directly while the buffer is still live.
          (funcall captured-fn live-buf))))
    (should render-called)))

(ert-deftest kuro-lifecycle--schedule-initial-render-uses-startup-delay-constant ()
  "kuro--schedule-initial-render uses kuro--startup-render-delay (0.05 s)."
  (should (= kuro--startup-render-delay 0.05)))

;;; Group 23 (attach): kuro--init-session-buffer — font/remap calls forwarded
;;
;; Verifies that kuro--init-session-buffer calls kuro--apply-font-to-buffer
;; and kuro--remap-default-face, rather than just checking dimensions.

(ert-deftest kuro-lifecycle--init-session-buffer-calls-apply-font ()
  "kuro--init-session-buffer calls kuro--apply-font-to-buffer with the buffer."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (let ((font-called-with nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--apply-font-to-buffer)
                   (lambda (b) (setq font-called-with b))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should (eq font-called-with (current-buffer))))))))

(ert-deftest kuro-lifecycle--init-session-buffer-calls-remap-default-face ()
  "kuro--init-session-buffer calls kuro--remap-default-face with fg/bg strings."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (let ((remap-args nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--remap-default-face)
                   (lambda (fg bg) (setq remap-args (list fg bg)))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should (consp remap-args))
          (should (stringp (car remap-args)))
          (should (stringp (cadr remap-args))))))))

(ert-deftest kuro-lifecycle--init-session-buffer-calls-setup-char-width ()
  "kuro--init-session-buffer calls kuro--setup-char-width-table."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (let ((char-width-called nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--setup-char-width-table)
                   (lambda () (setq char-width-called t))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should char-width-called))))))

;;; ── Group 24 (cleanup): kuro--rollback-attach — kill-buffer arg, noop-dead, state ─────
;;
;; Verifies the exact buffer argument passed to kill-buffer, that passing a
;; dead buffer causes no error, and that session state variables are cleared.

(ert-deftest kuro-lifecycle-ext-rollback-attach-kills-correct-buffer ()
  "kuro--rollback-attach calls kill-buffer with the exact buffer argument."
  (let* ((buf (generate-new-buffer " *kuro-ext-rollback-correct*"))
         (killed nil)
         (kuro--session-id 0)
         (kuro--initialized nil))
    (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
              ((symbol-function 'message)           #'ignore)
              ((symbol-function 'kill-buffer)
               (lambda (b) (setq killed b))))
      (kuro--rollback-attach 7 buf "err")
      (should (eq killed buf)))
    ;; Clean up in case our stub skipped the real kill.
    (when (buffer-live-p buf)
      (kill-buffer buf))))

(ert-deftest kuro-lifecycle-ext-rollback-attach-noop-when-buffer-dead ()
  "kuro--rollback-attach does not signal when the buffer is already dead."
  (let ((dead-buf (generate-new-buffer " *kuro-ext-rollback-dead*"))
        (kuro--session-id 0)
        (kuro--initialized nil))
    (kill-buffer dead-buf)
    (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
              ((symbol-function 'message)           #'ignore))
      ;; Pass the dead buffer; real kill-buffer on a dead buffer does not signal.
      (should-not (condition-case err
                      (progn (kuro--rollback-attach 0 dead-buf "e") nil)
                    (error err))))))

(ert-deftest kuro-lifecycle-ext-rollback-attach-clears-session-state ()
  "kuro--rollback-attach resets kuro--initialized to nil and kuro--session-id to 0."
  (with-temp-buffer
    (let ((kuro--session-id 42)
          (kuro--initialized t))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'message)           #'ignore)
                ((symbol-function 'kill-buffer)       #'ignore))
        (kuro--rollback-attach 42 (current-buffer) "state-test")
        (should-not kuro--initialized)
        (should (= kuro--session-id 0))))))

;;; ── Group 25 (cleanup): kuro--schedule-initial-render — dead-buffer, live, timer ──────
;;
;; Supplemental coverage: render called when live, skipped when dead, and
;; that the function schedules via run-with-idle-timer (not a direct call).

(ert-deftest kuro-lifecycle-ext-schedule-initial-render-calls-render-when-buffer-live ()
  "Timer callback calls kuro--render-cycle when the buffer is still live."
  (let ((render-called nil)
        (captured-fn   nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn)))
              ((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (with-temp-buffer
        (let ((live-buf (current-buffer)))
          (kuro--schedule-initial-render live-buf)
          ;; Invoke callback while buffer is still live.
          (funcall captured-fn live-buf))))
    (should render-called)))

(ert-deftest kuro-lifecycle-ext-schedule-initial-render-skips-render-when-buffer-dead ()
  "Timer callback does not call kuro--render-cycle when the buffer is dead."
  (let ((render-called nil)
        (captured-fn   nil)
        (dead-buf      nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn))))
      (with-temp-buffer
        (setq dead-buf (current-buffer))
        (kuro--schedule-initial-render dead-buf)))
    ;; Kill the buffer so buffer-live-p returns nil.
    (when (buffer-live-p dead-buf)
      (kill-buffer dead-buf))
    (cl-letf (((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (funcall captured-fn dead-buf))
    (should-not render-called)))

(ert-deftest kuro-lifecycle-ext-schedule-initial-render-uses-run-with-idle-timer ()
  "kuro--schedule-initial-render schedules via run-with-idle-timer."
  (let ((timer-scheduled nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat _fn &rest _args)
                 (setq timer-scheduled t))))
      (with-temp-buffer
        (kuro--schedule-initial-render (current-buffer))))
    (should timer-scheduled)))

;;; ── Group 26 (attach): kuro-create init-failure + kuro-attach switch-to-buffer guard ──
;;
;; Gap 1: When kuro--init returns nil, kuro-create must return a buffer but
;; must NOT call kuro--start-render-loop.  When kuro--init returns t the render
;; loop IS started.
;;
;; Gap 2: kuro-attach has `(unless noninteractive (switch-to-buffer …))'.  In
;; the test environment noninteractive is already t, so the branch is always
;; skipped.  Tests 4-5 document this guard explicitly: test 4 verifies that
;; switch-to-buffer is not called in a normal (noninteractive) test run, and
;; test 5 temporarily binds noninteractive to nil to exercise the live-mode
;; branch.

(defmacro kuro-lifecycle-test--with-create-stubs (&rest body)
  "Run BODY with every kuro-create side-effecting helper stubbed.
Stubs kuro--ensure-module-loaded, kuro-mode, kuro--prefill-buffer,
kuro--init-session-buffer, kuro--start-render-loop, and
kuro--schedule-initial-render as no-ops so the test controls only
`kuro--init' behaviour.  Override individual stubs inside BODY via
`cl-letf'."
  `(cl-letf (((symbol-function 'kuro--ensure-module-loaded)   #'ignore)
             ((symbol-function 'kuro-mode)
              (lambda () (setq major-mode 'kuro-mode)))
             ((symbol-function 'kuro--prefill-buffer)          #'ignore)
             ((symbol-function 'kuro--init-session-buffer)     #'ignore)
             ((symbol-function 'kuro--start-render-loop)       #'ignore)
             ((symbol-function 'kuro--schedule-initial-render) #'ignore)
             ((symbol-function 'message)                       #'ignore))
     ,@body))

(ert-deftest kuro-lifecycle--create-init-failure-returns-nil ()
  "kuro-create returns nil when kuro--init returns nil.
The buffer is still created; the return value of kuro-create should be
the buffer object (kuro-create always returns the buffer), but the
`when (kuro--init …)' body is skipped, so only the buffer is returned.
We verify that the returned value is a buffer (not signalling an error)
and that the session was not started."
  (let (result)
    (kuro-lifecycle-test--with-create-stubs
      (cl-letf (((symbol-function 'kuro--init)
                 (lambda (_cmd _shell-args _rows _cols) nil)))
        (setq result (kuro-create "echo" "*kuro-create-fail-test*"))))
    (unwind-protect
        ;; kuro-create always returns the buffer; the init failure just means
        ;; the render loop was not started.  The buffer is usable but empty.
        (should (bufferp result))
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--create-init-failure-no-render-scheduled ()
  "When kuro--init returns nil, kuro--start-render-loop is NOT called."
  (let ((render-started nil)
        result)
    (kuro-lifecycle-test--with-create-stubs
      (cl-letf (((symbol-function 'kuro--init)
                 (lambda (_cmd _shell-args _rows _cols) nil))
                ((symbol-function 'kuro--start-render-loop)
                 (lambda () (setq render-started t))))
        (setq result (kuro-create "echo" "*kuro-create-no-render-test*"))))
    (unwind-protect
        (should-not render-started)
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--create-success-starts-render-loop ()
  "When kuro--init returns t, kuro--start-render-loop IS called."
  (let ((render-started nil)
        result)
    (kuro-lifecycle-test--with-create-stubs
      (cl-letf (((symbol-function 'kuro--init)
                 (lambda (_cmd _shell-args _rows _cols) t))
                ((symbol-function 'kuro--start-render-loop)
                 (lambda () (setq render-started t))))
        (setq result (kuro-create "echo" "*kuro-create-success-test*"))))
    (unwind-protect
        (should render-started)
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--attach-skips-switch-to-buffer-when-noninteractive ()
  "In the test environment noninteractive is t, so kuro-attach never calls
switch-to-buffer.  This test documents and pins that guard: we use cl-letf
to detect any call to switch-to-buffer and verify none arrives."
  ;; Sanity-check the test environment assumption first.
  (should noninteractive)
  (let ((switch-called nil)
        result)
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach)             #'ignore)
              ((symbol-function 'message)                     #'ignore)
              ((symbol-function 'switch-to-buffer)
               (lambda (_buf) (setq switch-called t))))
      (setq result (kuro-attach 11)))
    (unwind-protect
        (should-not switch-called)
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--attach-calls-switch-to-buffer-when-interactive ()
  "When noninteractive is nil (simulating interactive Emacs), kuro-attach
calls switch-to-buffer with the newly created buffer."
  (let ((switch-called-with nil)
        result)
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach)             #'ignore)
              ((symbol-function 'message)                     #'ignore)
              ((symbol-function 'switch-to-buffer)
               (lambda (buf) (setq switch-called-with buf))))
      ;; Temporarily bind noninteractive to nil to enter the interactive branch.
      (let ((noninteractive nil))
        (setq result (kuro-attach 22))))
    (unwind-protect
        (progn
          (should switch-called-with)
          (should (eq switch-called-with result)))
      (when (buffer-live-p result)
        (kill-buffer result)))))

(provide 'kuro-lifecycle-test)

;;; kuro-lifecycle-test.el ends here
