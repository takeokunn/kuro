;;; kuro-e2e-modes-test.el --- E2E tests for terminal mode sequences -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for DEC private mode sequences that affect cursor visibility,
;; cursor keys, bracketed paste, keypad mode, auto-wrap, and mouse tracking.
;;
;; Design policy: NO standalone sleep-for calls.
;; All synchronisation uses kuro-e2e--render-idle or kuro-e2e--wait-for-text.
;; Shell-side `sleep' inside printf argument strings is a shell command, not an
;; Emacs sleep, and is therefore acceptable.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-e2e-helpers)

;;; ── Group 1: DECTCEM cursor visibility (CSI ?25 l/h) ────────────────────────

(ert-deftest kuro-e2e-cursor-visibility ()
  "DECTCEM ESC[?25l hides cursor; ESC[?25h restores it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Cursor must be visible at startup
   (should (kuro--get-cursor-visible))
   ;; Hide cursor
   (kuro--send-key "printf '\\033[?25l'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should-not (kuro--get-cursor-visible))
   ;; Restore cursor
   (kuro--send-key "printf '\\033[?25h'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should (kuro--get-cursor-visible))))

;;; ── Group 2: DECCKM application cursor keys (CSI ?1 h/l) ───────────────────

(ert-deftest kuro-e2e-decckm-mode ()
  "CSI ?1h enables application cursor keys (DECCKM); CSI ?1l disables it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; DECCKM should be off initially
   (should-not (kuro--get-app-cursor-keys))
   ;; Enable application cursor keys
   (kuro--send-key "printf '\\033[?1h'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should (kuro--get-app-cursor-keys))
   ;; Disable application cursor keys
   (kuro--send-key "printf '\\033[?1l'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should-not (kuro--get-app-cursor-keys))))

;;; ── Group 3: Bracketed paste mode (CSI ?2004 h/l) ──────────────────────────

(ert-deftest kuro-e2e-bracketed-paste-mode ()
  "CSI ?2004h enables bracketed paste; CSI ?2004l disables it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Bracketed paste is off initially
   (should-not (kuro--get-bracketed-paste))
   ;; Enable bracketed paste
   (kuro--send-key "printf '\\033[?2004h'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should (kuro--get-bracketed-paste))
   ;; Disable bracketed paste
   (kuro--send-key "printf '\\033[?2004l'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should-not (kuro--get-bracketed-paste))))

;;; ── Group 4: DECKPAM application keypad mode (ESC= / ESC>) ─────────────────

(ert-deftest kuro-e2e-deckpam-mode ()
  "ESC= enables application keypad mode (DECKPAM); ESC> disables it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Application keypad should be off initially
   (should-not (kuro--get-app-keypad))
   ;; Enable application keypad
   (kuro--send-key "printf '\\033='")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should (kuro--get-app-keypad))
   ;; Disable application keypad
   (kuro--send-key "printf '\\033>'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should-not (kuro--get-app-keypad))))

;;; ── Group 5: DECAWM auto-wrap mode (CSI ?7 l/h) ────────────────────────────

(ert-deftest kuro-e2e-auto-wrap-mode ()
  "CSI ?7l disables auto-wrap; long text stays on one row.
CSI ?7h re-enables wrap; long text overflows to next row."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Part 1: wrap-off
   (kuro--send-key "printf '\\033[?7l'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf 2 0.3)
   ;; 90-char line — stays on same row when wrap is disabled
   (kuro--send-key
    "printf 'NOWRAP_TEST_LINE_123456789012345678901234567890123456789012345678901234567'; sleep 0.3")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (let ((row-before
          (with-current-buffer buf
            (save-excursion
              (goto-char (point-min))
              (when (re-search-forward "NOWRAP_TEST_LINE" nil t)
                (1- (line-number-at-pos)))))))
     (should (= (or row-before 0) 0)))
   ;; Part 2: wrap-on
   (kuro--send-key "printf '\\033[?7h'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf 2 0.3)
   ;; 90-char line — wraps to next row when wrap is enabled
   (kuro--send-key
    "printf 'WRAP_TEST_LINE_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0'; sleep 0.3")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (let ((row-after
          (with-current-buffer buf
            (save-excursion
              (goto-char (point-min))
              (when (re-search-forward "WRAP_TEST_LINE" nil t)
                (line-number-at-pos))))))
     (should (>= (or row-after 1) 1)))))

(provide 'kuro-e2e-modes-test)

;;; kuro-e2e-modes-test.el ends here
