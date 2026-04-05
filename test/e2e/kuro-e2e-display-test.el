;;; kuro-e2e-display-test.el --- E2E tests for display/erase sequences -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for terminal display and erase sequences:
;; ED (erase in display), EL (erase in line), the `clear' command,
;; erase-from-start-to-cursor, and alternate screen buffer switching.
;;
;; All waiting uses kuro-e2e--wait-for-text / kuro-e2e--render-idle.
;; NO standalone sleep-for calls are permitted.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-e2e-helpers)

;;;; Group 1: `clear' command clears the visible screen

(ert-deftest kuro-e2e-clear-command ()
  "Running `clear' removes all prior content from the visible buffer."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "echo KBEFORECLEAR")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KBEFORECLEAR"))
   (kuro--send-key "clear")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should (not (string-match-p "KBEFORECLEAR" (buffer-string)))))))

;;;; Group 2: ED 0 — erase from cursor to end of display

(ert-deftest kuro-e2e-erase-display-to-end-ed0 ()
  "ESC[J (ED 0) erases from the cursor position to the end of the screen."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "echo KED0_MARK")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KED0_MARK"))
   (kuro--send-key "printf '\\033[1;1H\\033[J'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf 2 0.3)
   (kuro-e2e--render-idle buf 2 0.5)
   (with-current-buffer buf
     (should (not (string-match-p "KED0_MARK" (buffer-string)))))))

;;;; Group 3: ED 1 — erase from start of display to cursor

(ert-deftest kuro-e2e-erase-display-from-start-ed1 ()
  "ESC[1J (ED 1) erases from the top of the screen to the cursor position."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "echo KED1_MARK")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KED1_MARK"))
   (kuro--send-key "printf '\\033[24;80H\\033[1J'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf 2 0.3)
   (kuro-e2e--render-idle buf 2 0.5)
   (with-current-buffer buf
     (should (not (string-match-p "KED1_MARK" (buffer-string)))))))

;;;; Group 4: EL 0 — erase from cursor to end of line

(ert-deftest kuro-e2e-erase-line-to-end-el0-display ()
  "ESC[K (EL 0) erases from the cursor to the end of the line (display category)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print KEL0_AX, move back 1, erase to EOL, then print END.
   ;; Result: KEL0_AEND (X erased, replaced by END).
   (kuro--send-key "printf 'KEL0_AX\\033[1D\\033[KEND'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KEL0_AEND"))))

;;;; Group 5: Erase from start of screen to cursor (gap E04)

(ert-deftest kuro-e2e-erase-from-start-to-cursor ()
  "ED 1 after filling 15 rows erases rows 1-9; rows 10-15 remain visible."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Fill 15 rows with distinct markers.
   (dotimes (i 15)
     (kuro--send-key (format "echo ROW_%d" (1+ i)))
     (kuro--send-key "\r"))
   (should (kuro-e2e--wait-for-text buf "ROW_15"))
   ;; Move to row 9 col 1, insert ERASED text, then erase from start to cursor.
   ;; The shell sleep 0.3 is inside the shell printf command string, not Emacs.
   (kuro--send-key "printf '\\033[9;1HERASED\\033[1J'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string)))
       ;; Rows 10 and above should still be visible.
       (should (string-match-p "ROW_10" content))
       ;; Rows 1-5 were above the erase boundary and must be gone.
       (should (not (string-match-p "ROW_1\\b" content)))
       (should (not (string-match-p "ROW_5\\b" content)))))))

;;;; Group 6: Alternate screen buffer (ESC[?1049h / ESC[?1049l)

(ert-deftest kuro-e2e-alternate-screen-buffer ()
  "Switching to the alternate screen hides primary content; switching back restores it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Write a unique marker to the primary screen.
   (kuro--send-key "echo KALT_PRIMARY")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KALT_PRIMARY"))
   ;; Switch to alternate screen — primary content should disappear.
   (kuro--send-key "printf '\\033[?1049h'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should (not (string-match-p "KALT_PRIMARY" (buffer-string)))))
   ;; Switch back to primary screen — marker must reappear.
   (kuro--send-key "printf '\\033[?1049l'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should (string-match-p "KALT_PRIMARY" (buffer-string))))))

(provide 'kuro-e2e-display-test)

;;; kuro-e2e-display-test.el ends here
