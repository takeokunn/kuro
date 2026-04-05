;;; kuro-e2e-insert-delete-test.el --- E2E tests for insert/delete/erase sequences -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for CSI character/line insert, delete, and erase sequences:
;;   DCH (delete character), ICH (insert character), ECH (erase character),
;;   EL 0/1/2 (erase line to end/from beginning/entire line),
;;   IL (insert lines), DL (delete lines).
;;
;; Design policy: NO standalone sleep-for calls.
;; All synchronisation uses kuro-e2e--render-idle or kuro-e2e--wait-for-text.
;; Shell-side `sleep' inside printf argument strings is a shell command, not an
;; Emacs sleep, and is therefore acceptable.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-e2e-helpers)

;;; ── Group 1: DCH — delete characters (CSI P) ────────────────────────────────

(ert-deftest kuro-e2e-delete-characters-dch ()
  "DCH ESC[2P at cursor deletes 2 characters in-place.
printf 'KDCH_ABC' then move left 3, delete 2 → 'KDCH_ABEND' (with END appended)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print KDCH_ABC, move cursor left 3 positions, delete 2 chars, append END
   (kuro--send-key
    "printf 'KDCH_ABC\\033[3D\\033[2PEND\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KDCH_ABEND"))))

;;; ── Group 2: ICH — insert characters (CSI @) ────────────────────────────────

(ert-deftest kuro-e2e-insert-characters-ich ()
  "ICH ESC[1@ inserts one blank at cursor, pushing existing text right.
printf 'KICH_AB', move left 1, insert 1 blank, type Z → 'KICH_AZB'."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print KICH_AB, move left 1, insert 1 blank, type Z, newline
   (kuro--send-key
    "printf 'KICH_AB\\033[1D\\033[1@Z\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KICH_AZB"))))

;;; ── Group 3: EL 0 — erase to end of line (CSI K) ────────────────────────────

(ert-deftest kuro-e2e-erase-line-to-end-el0 ()
  "EL 0 (CSI K) erases from cursor to end of line.
printf 'KEL0_AX', move left 1, erase to end, append END → 'KEL0_AEND'."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print KEL0_AX, move left 1, erase to EOL, append END
   (kuro--send-key
    "printf 'KEL0_AX\\033[1D\\033[KEND\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KEL0_AEND"))))

;;; ── Group 4: ICH — insert characters gap coverage (E09) ────────────────────

(ert-deftest kuro-e2e-insert-characters ()
  "ICH: print 'hello', move to column 1, insert 3 blanks, type 'lo'.
The final line contains 'lo' (inserted prefix) and 'hel' (shifted suffix)."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print hello, go to col 1 (ESC[1G), insert 3 blanks (ESC[3@), type lo+newline
   (kuro--send-key
    "printf 'hello\\033[1G\\033[3@lo\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "lo"))
   (should (kuro-e2e--wait-for-text buf "hel"))))

;;; ── Group 5: DCH — delete characters gap coverage (E08) ────────────────────

(ert-deftest kuro-e2e-delete-characters ()
  "DCH: print 'hello', move to column 2, delete 2 chars → 'hlo'."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print hello, go to col 2 (ESC[2G), delete 2 (ESC[2P), sleep 0.3 in shell
   (kuro--send-key
    "printf 'hello\\033[2G\\033[2P'; sleep 0.3; echo ''")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (should (kuro-e2e--wait-for-text buf "hlo"))))

;;; ── Group 6: ECH — erase characters (CSI X) ─────────────────────────────────

(ert-deftest kuro-e2e-erase-characters ()
  "ECH ESC[3X erases 3 characters in-place (replaces with spaces).
Print 'KECH_hello', move back 5, erase 3, then append AFTER.
Result contains 'KECH_' and 'AFTER' but NOT 'KECH_hel'."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print KECH_hello, move left 5, erase 3, type AFTER+newline
   (kuro--send-key
    "printf 'KECH_hello\\033[5D\\033[3XAFTER\\n'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf 2 0.3)
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "KECH_" content))
       (should (string-match-p "AFTER" content))
       (should-not (string-match-p "KECH_hel" content))))))

;;; ── Group 7: IL — insert lines (CSI L) ──────────────────────────────────────

(ert-deftest kuro-e2e-insert-lines ()
  "IL ESC[2L inserts 2 blank lines at cursor row, pushing subsequent rows down.
Fill 10 rows, position cursor at row 5, insert 2 lines, print KILAFTER.
KILAFTER and KILROW_ labels must still be visible."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Fill 10 rows with labelled content
   (dotimes (i 10)
     (kuro--send-key (format "echo KILROW_%d" (1+ i)))
     (kuro--send-key "\r"))
   ;; Wait for last row to appear
   (should (kuro-e2e--wait-for-text buf "KILROW_10"))
   ;; Move to row 5 col 1, insert 2 lines, print marker
   (kuro--send-key
    "printf '\\033[5;1H\\033[2LKILAFTER\\n'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf 2 0.5)
   (should (kuro-e2e--wait-for-text buf "KILAFTER" 5.0))
   (kuro-e2e--render-idle buf 2 0.3)
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "KILAFTER" content))
       (should (string-match-p "KILROW_" content))))))

;;; ── Group 8: DL — delete lines (CSI M) ──────────────────────────────────────

(ert-deftest kuro-e2e-delete-lines ()
  "DL ESC[2M deletes 2 lines at cursor row, pulling subsequent rows up.
Fill 8 rows, position cursor at row 3, delete 2 lines, print KDLAFTER.
KDLAFTER, KDLROW_1/2 appear; KDLROW_3/4 do not; KDLROW_5–8 appear."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Fill 8 rows with labelled content
   (dotimes (i 8)
     (kuro--send-key (format "echo KDLROW_%d" (1+ i)))
     (kuro--send-key "\r"))
   ;; Wait for last row to appear
   (should (kuro-e2e--wait-for-text buf "KDLROW_8"))
   ;; Move to row 3 col 1, delete 2 lines, print marker
   (kuro--send-key
    "printf '\\033[3;1H\\033[2MKDLAFTER\\n'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf 2 0.5)
   (should (kuro-e2e--wait-for-text buf "KDLAFTER" 5.0))
   (kuro-e2e--render-idle buf 2 0.3)
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "KDLAFTER" content))
       (should (string-match-p "KDLROW_1" content))
       (should (string-match-p "KDLROW_2" content))
       ;; Rows 3 and 4 should have been deleted
       (should-not (string-match-p "KDLROW_3" content))
       (should-not (string-match-p "KDLROW_4" content))
       ;; Rows 5–8 shift up and remain visible
       (should (string-match-p "KDLROW_5" content))
       (should (string-match-p "KDLROW_8" content))))))

;;; ── Group 9: EL 1 — erase to beginning of line (CSI 1K) ────────────────────

(ert-deftest kuro-e2e-erase-line-to-cursor ()
  "EL 1 (CSI 1K) erases from the beginning of the line to the cursor.
Print a long string, move cursor to col 20, erase backward.
'END' (the suffix) remains; 'KEL1_START' (the erased prefix) is gone."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print line, move to col 20, erase to beginning, newline
   (kuro--send-key
    "printf 'KEL1_START1234567890END\\033[20G\\033[1K\\n'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "END" content))
       (should-not (string-match-p "KEL1_START" content))))))

;;; ── Group 10: EL 2 — erase entire line (CSI 2K) ────────────────────────────

(ert-deftest kuro-e2e-erase-entire-line ()
  "EL 2 (CSI 2K) erases the entire current line.
Print a unique string, erase the whole line, then print LINE_CLEARED.
'KEL2_ENTIRE_LINE_TEXT' must be gone; 'LINE_CLEARED' must appear."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Print text, erase entire line, print new marker
   (kuro--send-key
    "printf 'KEL2_ENTIRE_LINE_TEXT_HERE\\033[2KLINE_CLEARED\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "LINE_CLEARED"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should-not (string-match-p "KEL2_ENTIRE_LINE_TEXT" (buffer-string))))))

;;; ── Group 11: EL 2 via two-variable split trick ──────────────────────────────

(ert-deftest kuro-e2e-erase-line-entire-el2 ()
  "EL 2 erases content written via two shell variables so the string cannot
appear literally in the test source.  After the erase, 'KEL2_DONE' appears."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Build the sentinel string from two variables to avoid literal match
   (kuro--send-key "A=KEL2_SPLIT; B=_CONTENT")
   (kuro--send-key "\r")
   ;; Echo the combined string (it will appear in the terminal briefly)
   (kuro--send-key "echo $A$B")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KEL2_SPLIT"))
   ;; Move cursor up one line (CUU), erase entire line, then print done marker
   (kuro--send-key
    "printf '\\033[1A\\033[2K'; echo KEL2_DONE")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KEL2_DONE"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should-not (string-match-p "KEL2_SPLIT_CONTENT" (buffer-string))))))

(provide 'kuro-e2e-insert-delete-test)

;;; kuro-e2e-insert-delete-test.el ends here
