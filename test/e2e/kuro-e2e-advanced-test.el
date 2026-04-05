;;; kuro-e2e-advanced-test.el --- E2E tests for advanced terminal features -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for advanced Kuro features:
;;   - OSC 0 title propagation (PTY → Rust → FFI → Emacs buffer name)
;;   - BEL byte triggering `ding'
;;   - Ctrl+L screen clear leaving shell responsive
;;
;; Design policy: NO standalone sleep-for calls.
;; All synchronisation uses kuro-e2e--render-idle or kuro-e2e--wait-for-text.
;; Conditional sleep-for inside polling loops is acceptable.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-e2e-helpers)

;;; ── Group 1: OSC 0 title integration ────────────────────────────────────────

(ert-deftest kuro-e2e-osc-title-integration ()
  "OSC 0 title sequence propagates through PTY→Rust→FFI→Emacs buffer name.
The test sends an OSC 0 sequence, confirms the shell echoed a marker, then
polls until the buffer is renamed to include the title string."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Send OSC 0 title sequence followed by a visible marker
   (kuro--send-key "printf '\\033]0;kuro-title-test\\007' && echo OSC_TITLE_SENT")
   (kuro--send-key "\r")
   ;; Wait for the shell to confirm the command ran
   (should (kuro-e2e--wait-for-text buf "OSC_TITLE_SENT"))
   ;; Poll until buffer name reflects the OSC title
   (should (kuro-e2e--wait-for-buffer-name buf "kuro-title-test"))))

;;; ── Group 2: BEL character triggers ding ────────────────────────────────────

(ert-deftest kuro-e2e-bell-character ()
  "A BEL byte (\\a) sent through the PTY causes `ding' to be called.
The test mocks `ding', sends the bell, lets the renderer process the frame,
then manually flushes the pending bell queue."
  :expected-result kuro-e2e--expected-result
  (require 'kuro-renderer)
  (kuro-e2e--with-terminal
   (let ((ding-called nil))
     (cl-letf (((symbol-function 'ding)
                (lambda (&optional _arg) (setq ding-called t))))
       ;; Send BEL byte via shell printf
       (kuro--send-key "printf '\\a'")
       (kuro--send-key "\r")
       ;; Wait for the PTY frame to arrive and be rendered
       (kuro-e2e--render-idle buf)
       ;; Run a final render pass to ensure output is fully processed
       (kuro-e2e--render buf)
       ;; Flush the pending bell (may be deferred by the renderer)
       (with-current-buffer buf (kuro--ring-pending-bell))
       (should ding-called)))))

;;; ── Group 3: Ctrl+L clears screen but keeps shell responsive ────────────────

(ert-deftest kuro-e2e-ctrl-l-clear-screen ()
  "Ctrl+L (form-feed, \\x0c) clears the visible screen without hanging the shell.
Verifies that output produced before and after the clear both appear."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Produce output before the clear
   (kuro--send-key "echo KBEFORECTRL")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KBEFORECTRL"))
   ;; Send Ctrl+L
   (kuro--send-key "\x0c")
   ;; Let the renderer quiesce after the clear (no fixed sleep)
   (kuro-e2e--render-idle buf)
   ;; Produce output after the clear — shell must still be responsive
   (kuro--send-key "echo KAFTERCTRL")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KAFTERCTRL"))))

(provide 'kuro-e2e-advanced-test)

;;; kuro-e2e-advanced-test.el ends here
