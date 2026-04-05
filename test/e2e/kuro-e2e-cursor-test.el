;;; kuro-e2e-cursor-test.el --- E2E tests for cursor movement sequences -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for cursor movement escape sequences:
;; CUU (cursor up), CUD (cursor down), CUF (cursor forward), CUB (cursor back),
;; CHA (cursor horizontal absolute), VPA (vertical position absolute),
;; and direct row/col movement sequences.
;;
;; All waiting uses kuro-e2e--wait-for-text / kuro-e2e--render-idle.
;; NO standalone sleep-for calls are permitted.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-e2e-helpers)

;;;; Group 1: CUU — cursor up (ESC[nA)

(ert-deftest kuro-e2e-cursor-up-cuu ()
  "CUU ESC[1A moves cursor up one row; X overwrites on the row above."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf 'KCUU_A\\nKCUU_B\\033[1AX'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should (kuro-e2e--wait-for-text buf "KCUU_AX"))))

;;;; Group 2: CUB — cursor backward (ESC[nD)

(ert-deftest kuro-e2e-cursor-backward-cub ()
  "CUB ESC[5D moves cursor 5 columns left; X overwrites the first column."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf 'KCUB_ABCDE\\033[5DX'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KCUB_XBCDE"))))

;;;; Group 3: CUF — cursor forward (ESC[nC)

(ert-deftest kuro-e2e-cursor-forward-cuf ()
  "CUF ESC[3C moves cursor 3 columns right; X overwrites the fourth character."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf 'KCUF_ABCDE\\033[5D\\033[3CX'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KCUF_ABCXE"))))

;;;; Group 4: CHA — cursor horizontal absolute (ESC[nG)

(ert-deftest kuro-e2e-cursor-cha ()
  "CHA ESC[1G moves cursor to column 1 (0-indexed col 0)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[2J\\033[H\\033[1G'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (cdr cursor) 0))))))

;;;; Group 5: CUD — cursor down (ESC[nB)

(ert-deftest kuro-e2e-cursor-down-cud ()
  "CUD ESC[1B moves cursor down one row; X appends to second row."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf 'KCUDA\\nKCUDB\\033[1A\\033[1BX'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KCUDBX"))))

;;;; Group 6: CUU movement — absolute row check (gap E10)

(ert-deftest kuro-e2e-cursor-up-movement ()
  "ESC[5A from row 11 places cursor at row 6 (0-indexed row 5)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[11;1H\\033[5A'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (car cursor) 5))))))

;;;; Group 7: CUD movement — absolute row check (gap E11)

(ert-deftest kuro-e2e-cursor-down-movement ()
  "ESC[3B from the home position places cursor at row 4 (0-indexed row 3)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[H\\033[3B'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (car cursor) 3))))))

;;;; Group 8: CUB movement — absolute col check (gap E12)

(ert-deftest kuro-e2e-cursor-left-movement ()
  "ESC[5D from column 11 places cursor at column 6 (0-indexed col 5)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[11G\\033[5D'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (cdr cursor) 5))))))

;;;; Group 9: CUF movement — absolute col check (gap E13)

(ert-deftest kuro-e2e-cursor-right-movement ()
  "ESC[10C from column 1 places cursor at column 11 (0-indexed col 10)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[G\\033[10C'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (cdr cursor) 10))))))

;;;; Group 10: CHA absolute column (gap E14)

(ert-deftest kuro-e2e-character-position-absolute ()
  "ESC[40G places cursor at column 40 (0-indexed col 39)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[40G'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (cdr cursor) 39))))))

;;;; Group 11: VPA — vertical position absolute (gap E15)

(ert-deftest kuro-e2e-vertical-position-absolute ()
  "ESC[12d places cursor at row 12 (0-indexed row 11)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[12d'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((cursor (kuro--get-cursor)))
       (should (= (car cursor) 11))))))

(provide 'kuro-e2e-cursor-test)

;;; kuro-e2e-cursor-test.el ends here
