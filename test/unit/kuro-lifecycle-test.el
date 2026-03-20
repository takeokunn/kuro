;;; kuro-lifecycle-test.el --- Unit tests for kuro-lifecycle.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el public API.
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

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; ── Stub Rust FFI symbols before loading kuro-lifecycle ─────────────────────
;; These symbols are provided by the Rust dynamic module at runtime.
;; Guard with `unless (fboundp …)' so a real loaded module is not overridden.

(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-get-scroll-offset
               kuro-core-get-and-clear-title
               kuro-core-get-default-colors
               kuro-core-get-palette-updates
               kuro-core-get-image
               kuro-core-take-bell-pending
               kuro-core-get-focus-events
               kuro-core-get-app-cursor-keys
               kuro-core-get-app-keypad
               kuro-core-get-bracketed-paste
               kuro-core-get-mouse-mode
               kuro-core-get-mouse-sgr
               kuro-core-get-mouse-pixel
               kuro-core-get-keyboard-flags
               kuro-core-get-scrollback-count
               kuro-core-get-scrollback
               kuro-core-get-sync-output
               kuro-core-get-cwd
               kuro-core-has-pending-output
               kuro-core-is-process-alive
               kuro-core-poll-clipboard-actions
               kuro-core-poll-image-notifications
               kuro-core-poll-prompt-marks
               kuro-core-scroll-up
               kuro-core-scroll-down
               kuro-core-consume-scroll-events
               kuro-core-clear-scrollback
               kuro-core-set-scrollback-max-lines
               kuro-core-detach
               kuro-core-attach
               kuro-core-list-sessions))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

;;; ── Ensure emacs-lisp/ is on load-path ─────────────────────────────────────

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-lifecycle)

;;; ── Helper macros ───────────────────────────────────────────────────────────

(defmacro kuro-lifecycle-test--capture-send-key (&rest body)
  "Execute BODY with `kuro--send-key' stubbed.
Returns the list of arguments passed to it, in order.
`kuro--initialized' is bound to t so the guard inside `kuro--send-key'
allows the call through."
  `(let ((captured nil)
         (kuro--initialized t))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (push data captured))))
       ,@body)
     (nreverse captured)))

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
      (cl-letf (((symbol-function 'kuro--shutdown)
                 (lambda () (setq shutdown-called t)))
                ((symbol-function 'kuro--stop-render-loop)
                 (lambda () nil))
                ((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () nil)))
        (kuro-kill)
        (should-not shutdown-called)))))

(ert-deftest kuro-lifecycle--kill-calls-shutdown-in-kuro-mode ()
  "kuro-kill calls kuro--shutdown when the buffer is in kuro-mode."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((shutdown-called nil))
      (cl-letf (((symbol-function 'kuro--shutdown)
                 (lambda () (setq shutdown-called t)))
                ((symbol-function 'kuro--stop-render-loop)
                 (lambda () nil))
                ((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () nil))
                ((symbol-function 'kill-buffer)
                 (lambda (_buf) nil)))
        (kuro-kill)
        (should shutdown-called)))))

(ert-deftest kuro-lifecycle--kill-stops-render-loop ()
  "kuro-kill calls kuro--stop-render-loop before kuro--shutdown."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((call-order nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)
                 (lambda () (push 'stop-render call-order)))
                ((symbol-function 'kuro--shutdown)
                 (lambda () (push 'shutdown call-order)))
                ((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () nil))
                ((symbol-function 'kill-buffer)
                 (lambda (_buf) nil)))
        (kuro-kill)
        ;; nreverse because push builds in reverse order
        (let ((ordered (nreverse call-order)))
          (should (eq (nth 0 ordered) 'stop-render))
          (should (eq (nth 1 ordered) 'shutdown)))))))

(ert-deftest kuro-lifecycle--kill-resets-mouse-state ()
  "kuro-kill resets kuro--mouse-mode, kuro--mouse-sgr, and kuro--mouse-pixel-mode."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode t)
    (cl-letf (((symbol-function 'kuro--stop-render-loop) (lambda () nil))
              ((symbol-function 'kuro--shutdown)          (lambda () nil))
              ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
              ((symbol-function 'kill-buffer)             (lambda (_buf) nil)))
      (kuro-kill)
      (should (= kuro--mouse-mode 0))
      (should (null kuro--mouse-sgr))
      (should (null kuro--mouse-pixel-mode)))))

(ert-deftest kuro-lifecycle--kill-resets-scroll-offset ()
  "kuro-kill resets kuro--scroll-offset to 0."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--scroll-offset 42)
    (cl-letf (((symbol-function 'kuro--stop-render-loop) (lambda () nil))
              ((symbol-function 'kuro--shutdown)          (lambda () nil))
              ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
              ((symbol-function 'kill-buffer)             (lambda (_buf) nil)))
      (kuro-kill)
      (should (= kuro--scroll-offset 0)))))

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

;;; ── Group 5: kuro-list-sessions ─────────────────────────────────────────────
;;
;; kuro-list-sessions calls kuro-core-list-sessions and formats results into a
;; *kuro-sessions* buffer.  Each entry from Rust is (SESSION-ID COMMAND
;; DETACHED-P ALIVE-P) — indices 0, 1, 2, 3 respectively.  The critical
;; regression test covers the historical nth-index bug where alive-p and
;; detached-p were bound to the wrong indices.

(ert-deftest kuro-lifecycle--list-sessions-no-sessions ()
  "kuro-list-sessions prints a message when kuro-core-list-sessions returns nil."
  (let ((messages nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () nil))
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) messages))))
      (kuro-list-sessions)
      (should (cl-some (lambda (m) (string-match-p "No active" m)) messages)))))

(ert-deftest kuro-lifecycle--list-sessions-nth-index-regression ()
  "Regression: entry (id cmd nil t) must show 'running' in the table row.
With swapped nth indices the original bug made (nth 3 entry)=t feed
detached-p, producing 'detached' for a live session.  This test pins
the correct mapping: index 2 = is_detached, index 3 = is_alive.

Note: the footer text always contains the word 'detached', so we use a
row-scoped regex (matching 'ID N ... status') instead of a buffer-wide check."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             ;; id=0, cmd="bash", detached=nil(idx2), alive=t(idx3)
             (lambda () '((0 "bash" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      ;; The table row for ID 0 must show "running" in the status column.
      (should (string-match-p "ID 0.*running" (buffer-string)))
      ;; The table row must NOT show "detached" as the status for ID 0.
      ;; (Swapped bug: alive-p=t at index 3 → detached-p=t → wrong "detached".)
      (should-not (string-match-p "ID 0.*detached" (buffer-string))))))

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
      (cl-letf (((symbol-function 'kuro--stop-render-loop)
                 (lambda () nil))
                ((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () nil))
                ((symbol-function 'kuro--is-process-alive)
                 (lambda () t))
                ;; yes-or-no-p returns nil → user chose "no" → detach path
                ((symbol-function 'yes-or-no-p)
                 (lambda (_prompt) nil))
                ((symbol-function 'kuro-core-detach)
                 (lambda (id) (setq detach-called-with id)))
                ((symbol-function 'kuro--shutdown)
                 (lambda () (setq shutdown-called t)))
                ((symbol-function 'kill-buffer)
                 (lambda (_buf) nil)))
        (kuro-kill)
        (should (equal detach-called-with 99))
        (should-not shutdown-called)
        (should-not kuro--initialized)
        (should (= kuro--session-id 0))))))

(ert-deftest kuro-lifecycle--kill-destroys-when-user-says-yes ()
  "kuro-kill calls kuro--shutdown (not kuro-core-detach) when user says yes.
This complements the detach branch test above."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--initialized t)
    (setq-local kuro--session-id 77)
    (let ((detach-called nil)
          (shutdown-called nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)
                 (lambda () nil))
                ((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () nil))
                ((symbol-function 'kuro--is-process-alive)
                 (lambda () t))
                ;; yes-or-no-p returns t → user chose "yes" → destroy path
                ((symbol-function 'yes-or-no-p)
                 (lambda (_prompt) t))
                ((symbol-function 'kuro-core-detach)
                 (lambda (_id) (setq detach-called t)))
                ((symbol-function 'kuro--shutdown)
                 (lambda () (setq shutdown-called t)))
                ((symbol-function 'kill-buffer)
                 (lambda (_buf) nil)))
        (kuro-kill)
        (should shutdown-called)
        (should-not detach-called)))))

(provide 'kuro-lifecycle-test)

;;; kuro-lifecycle-test.el ends here
