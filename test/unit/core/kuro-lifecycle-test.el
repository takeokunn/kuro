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

(provide 'kuro-lifecycle-test)

;;; kuro-lifecycle-test.el ends here
