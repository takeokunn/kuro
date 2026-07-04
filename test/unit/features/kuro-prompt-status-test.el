;;; kuro-prompt-status-test.el --- Unit tests for kuro-prompt-status.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-prompt-status.el (prompt exit-status indicators).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Groups:
;;   Group 1: kuro--prompt-status-indicator — return values
;;   Group 2: kuro--apply-prompt-status-overlay — overlay creation
;;   Group 3: kuro--clear-prompt-status-overlays — cleanup
;;   Group 4: kuro--update-prompt-status — mark processing
;;   Group 5: kuro--ensure-left-margin — margin setup
;;   Group 6: faces and defcustom defaults

;;; Code:

(require 'ert)
(require 'kuro-prompt-status-test-support)

;;; Group 1: kuro--prompt-status-indicator — return values

(ert-deftest kuro-prompt-status--indicator-nil-for-nil-exit-code ()
  "kuro--prompt-status-indicator returns nil when exit-code is nil."
  (should (null (kuro--prompt-status-indicator nil))))

(kuro-prompt-status-test--def-indicator-result
 kuro-prompt-status--indicator-success-for-zero    0 "✓" kuro-prompt-success)
(kuro-prompt-status-test--def-indicator-result
 kuro-prompt-status--indicator-failure-for-nonzero 1 "✗" kuro-prompt-failure)

(ert-deftest kuro-prompt-status--indicator-all-exit-codes-correct ()
  "Invariant: indicator returns correct text+face for both success and failure exit codes."
  (dolist (entry kuro-prompt-status-test--indicator-result-table)
    (pcase-let ((`(,_name ,exit-code ,expected-text ,expected-face) entry))
      (let ((result (kuro--prompt-status-indicator exit-code)))
        (should (stringp result))
        (should (string= (substring-no-properties result) expected-text))
        (should (eq (get-text-property 0 'face result) expected-face))))))

;;; Group 2: kuro--apply-prompt-status-overlay — overlay creation

(ert-deftest kuro-prompt-status--apply-overlay-creates-at-correct-row ()
  "kuro--apply-prompt-status-overlay creates an overlay at the specified row."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (let ((indicator (propertize "✓" 'face 'kuro-prompt-success)))
      (kuro--apply-prompt-status-overlay 3 indicator)
      (should (= (length kuro--prompt-status-overlays) 1))
      (let ((ov (car kuro--prompt-status-overlays)))
        (should (overlay-get ov 'kuro-prompt-status))
        ;; Overlay should be at the start of row 3 (4th line).
        (save-excursion
          (goto-char (point-min))
          (forward-line 3)
          (should (= (overlay-start ov) (point))))))))

(ert-deftest kuro-prompt-status--apply-overlay-pushes-to-list ()
  "kuro--apply-prompt-status-overlay pushes new overlay onto the list."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 5) (insert "line\n"))
    (let ((indicator (propertize "✗" 'face 'kuro-prompt-failure)))
      (kuro--apply-prompt-status-overlay 0 indicator)
      (kuro--apply-prompt-status-overlay 2 indicator)
      (should (= (length kuro--prompt-status-overlays) 2)))))

;;; Group 3: kuro--clear-prompt-status-overlays — cleanup

(ert-deftest kuro-prompt-status--clear-overlays-removes-all ()
  "kuro--clear-prompt-status-overlays deletes all overlays and empties the list."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 5) (insert "line\n"))
    (let ((indicator (propertize "✓" 'face 'kuro-prompt-success)))
      (kuro--apply-prompt-status-overlay 0 indicator)
      (kuro--apply-prompt-status-overlay 2 indicator)
      (should (= (length kuro--prompt-status-overlays) 2))
      (kuro--clear-prompt-status-overlays)
      (should (null kuro--prompt-status-overlays))
      ;; No overlays with kuro-prompt-status property should remain.
      (let ((remaining (seq-filter
                        (lambda (ov) (overlay-get ov 'kuro-prompt-status))
                        (overlays-in (point-min) (point-max)))))
        (should (null remaining))))))

(ert-deftest kuro-prompt-status--clear-overlays-noop-when-empty ()
  "kuro--clear-prompt-status-overlays is a no-op when the list is already nil."
  (kuro-prompt-status-test--with-buffer
    (kuro--clear-prompt-status-overlays)
    (should (null kuro--prompt-status-overlays))))

(ert-deftest kuro-prompt-status--clear-overlays-skips-dead-overlay ()
  "kuro--clear-prompt-status-overlays does not error on an already-deleted overlay."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 3) (insert "line\n"))
    (let ((indicator (propertize "✓" 'face 'kuro-prompt-success)))
      (kuro--apply-prompt-status-overlay 0 indicator)
      ;; Pre-delete the first overlay so overlay-buffer returns nil
      (delete-overlay (car kuro--prompt-status-overlays))
      ;; clear must not error even though the overlay is dead
      (kuro--clear-prompt-status-overlays)
      (should (null kuro--prompt-status-overlays)))))

;;; Group 4: kuro--update-prompt-status — mark processing

(ert-deftest kuro-prompt-status--update-processes-command-end-marks ()
  "kuro--update-prompt-status creates overlays for command-end marks with exit codes."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (kuro--update-prompt-status
     '(("command-end" 2 0 0)
       ("command-end" 5 0 1)))
    (should (= (length kuro--prompt-status-overlays) 2))))

(ert-deftest kuro-prompt-status--update-ignores-non-command-end ()
  "kuro--update-prompt-status ignores marks that are not command-end."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (kuro--update-prompt-status
     '(("prompt-start" 2 0 nil)
       ("command-start" 3 0 nil)
       ("command-end" 5 0 0)))
    (should (= (length kuro--prompt-status-overlays) 1))))

(ert-deftest kuro-prompt-status--update-respects-toggle ()
  "kuro--update-prompt-status does nothing when annotations are disabled."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (let ((kuro-prompt-status-annotations nil))
      (kuro--update-prompt-status
       '(("command-end" 2 0 0)))
      (should (null kuro--prompt-status-overlays)))))

;;; Group 4b: kuro--update-prompt-status — 7-tuple destructure & extras

(ert-deftest kuro-prompt-status--update-7tuple-renders-indicator-only ()
  "T2a: 7-tuple with all-nil extras still renders the exit-code indicator."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (kuro--update-prompt-status
     '(("command-end" 4 0 0 nil nil nil)))
    ;; Only the indicator overlay; no extras overlay since all extras nil.
    (should (= (length kuro--prompt-status-overlays) 1))
    (let ((ov (car kuro--prompt-status-overlays)))
      (should (overlay-get ov 'kuro-prompt-status))
      (should-not (overlay-get ov 'kuro-prompt-extras)))))

(ert-deftest kuro-prompt-status--update-renders-extras-when-aid-set ()
  "T2b: extras overlay is created when aid is non-nil."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (kuro--update-prompt-status
     '(("command-end" 2 0 0 "job1" nil nil)))
    ;; Indicator + extras = 2 overlays.
    (should (= (length kuro--prompt-status-overlays) 2))
    (let ((extras (seq-find (lambda (ov) (overlay-get ov 'kuro-prompt-extras))
                            kuro--prompt-status-overlays)))
      (should extras)
      (should (string-match-p "aid=job1" (overlay-get extras 'after-string))))))

(ert-deftest kuro-prompt-status--update-formats-duration-1500-as-1.5s ()
  "T2c: duration-ms 1500 renders as \"1.5s\"."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (kuro--update-prompt-status
     '(("command-end" 1 0 0 nil 1500 nil)))
    (let ((extras (seq-find (lambda (ov) (overlay-get ov 'kuro-prompt-extras))
                            kuro--prompt-status-overlays)))
      (should extras)
      (should (string-match-p "1\\.5s" (overlay-get extras 'after-string))))))

(ert-deftest kuro-prompt-status--update-formats-duration-75000-as-1m15s ()
  "T2d: duration-ms 75000 renders as \"1m15s\"."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (kuro--update-prompt-status
     '(("command-end" 1 0 0 nil 75000 nil)))
    (let ((extras (seq-find (lambda (ov) (overlay-get ov 'kuro-prompt-extras))
                            kuro--prompt-status-overlays)))
      (should extras)
      (should (string-match-p "1m15s" (overlay-get extras 'after-string))))))

(ert-deftest kuro-prompt-status--update-skips-extras-when-toggle-off ()
  "T2e: extras overlay is suppressed when kuro-prompt-status-show-extras is nil."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (let ((kuro-prompt-status-show-extras nil))
      (kuro--update-prompt-status
       '(("command-end" 3 0 0 "job1" 1500 "/tmp/log"))))
    ;; Only the indicator overlay; extras suppressed.
    (should (= (length kuro--prompt-status-overlays) 1))
    (should-not (seq-find (lambda (ov) (overlay-get ov 'kuro-prompt-extras))
                          kuro--prompt-status-overlays))))

(ert-deftest kuro-prompt-status--format-extras-all-nil-returns-nil ()
  "T2f: kuro--format-prompt-extras with all nil fields returns nil."
  (should (null (kuro--format-prompt-extras nil nil nil))))

(ert-deftest kuro-prompt-status--update-accepts-legacy-4-tuple ()
  "Backward-compat: the dotted-rest pcase pattern still matches a 4-tuple."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    ;; Old-shape 4-tuple — extras are absent (nil), indicator still rendered.
    (kuro--update-prompt-status '(("command-end" 2 0 1)))
    (should (= (length kuro--prompt-status-overlays) 1))
    (should-not (seq-find (lambda (ov) (overlay-get ov 'kuro-prompt-extras))
                          kuro--prompt-status-overlays))))

(ert-deftest kuro-prompt-status--format-extras-includes-err-path ()
  "Extras include err= prefix when err-path is provided."
  (let ((s (kuro--format-prompt-extras nil nil "/tmp/build.log")))
    (should (stringp s))
    (should (string-match-p "err=/tmp/build\\.log" s))))

(ert-deftest kuro-prompt-status--format-extras-sanitizes-control-and-bidi ()
  "aid/err-path from untrusted OSC 133 marks are stripped of control+bidi chars.
Prevents prompt-line reordering and spoofing via crafted D-mark fields."
  (let ((s (kuro--format-prompt-extras "a\e[31m‮b" nil "/tmp/\r\afake")))
    (should (stringp s))
    ;; The ESC, CR, BEL control bytes and the RTL override (U+202E) are stripped,
    ;; while the printable residue (e.g. "[31m") is preserved verbatim.
    (should (string-match-p "aid=a\\[31mb" s))
    (should (string-match-p "err=/tmp/fake" s))
    (should-not (string-match-p "[\x00-\x1f\x7f‮]" s))))

(ert-deftest kuro-prompt-status--sanitize-prompt-extra-nil-passthrough ()
  "kuro--sanitize-prompt-extra returns nil unchanged for nil input."
  (should (null (kuro--sanitize-prompt-extra nil))))

(ert-deftest kuro-prompt-status--sanitize-prompt-extra-strips-alm-and-lrm ()
  "kuro--sanitize-prompt-extra also strips ALM (U+061C) and LRM (U+200E).
Regression: these bidi-control characters are in the same spoofing family as
the override/isolate characters already covered, but were missed initially."
  (should (equal (kuro--sanitize-prompt-extra "a؜b‎c") "abc")))

(ert-deftest kuro-prompt-status--format-duration-sub-second ()
  "Duration <1000ms renders as \"Nms\"."
  (should (equal (kuro--format-prompt-duration 250) "250ms")))

;;; Group 4c: kuro--format-prompt-duration — band boundary values

(kuro-prompt-status-test--def-format-duration kuro-prompt-status--format-duration-0ms       0       "0ms")
(kuro-prompt-status-test--def-format-duration kuro-prompt-status--format-duration-999ms     999     "999ms")
(kuro-prompt-status-test--def-format-duration kuro-prompt-status--format-duration-1000ms    1000    "1.0s")
(kuro-prompt-status-test--def-format-duration kuro-prompt-status--format-duration-59999ms   59999   "60.0s")
(kuro-prompt-status-test--def-format-duration kuro-prompt-status--format-duration-60000ms   60000   "1m00s")
(kuro-prompt-status-test--def-format-duration kuro-prompt-status--format-duration-3600000ms 3600000 "60m00s")

(ert-deftest kuro-prompt-status--format-duration-all-bands-correct ()
  "Every entry in `kuro-prompt-status-test--format-duration-table' formats correctly."
  (dolist (entry kuro-prompt-status-test--format-duration-table)
    (pcase-let ((`(,_name ,ms ,expected) entry))
      (should (equal (kuro--format-prompt-duration ms) expected)))))

;;; Group 5: kuro--ensure-left-margin — margin setup

(ert-deftest kuro-prompt-status--ensure-left-margin-sets-width ()
  "kuro--ensure-left-margin sets left-margin-width to 2 when unset."
  (with-temp-buffer
    (let ((kuro-prompt-status-annotations t)
          (left-margin-width nil))
      (kuro--ensure-left-margin)
      (should (= left-margin-width 2)))))

(ert-deftest kuro-prompt-status--ensure-left-margin-noop-when-annotations-off ()
  "kuro--ensure-left-margin does nothing when annotations are disabled."
  (with-temp-buffer
    (let ((kuro-prompt-status-annotations nil)
          (left-margin-width nil))
      (kuro--ensure-left-margin)
      (should (null left-margin-width)))))

(ert-deftest kuro-prompt-status--ensure-left-margin-noop-when-already-wide ()
  "kuro--ensure-left-margin does nothing when left-margin-width is already 2."
  (with-temp-buffer
    (let ((kuro-prompt-status-annotations t)
          (left-margin-width 2))
      (kuro--ensure-left-margin)
      (should (= left-margin-width 2)))))

;;; Group 6: faces and defcustom defaults

(kuro-prompt-status-test--def-face-exists kuro-prompt-status--success-face-exists kuro-prompt-success)
(kuro-prompt-status-test--def-face-exists kuro-prompt-status--failure-face-exists kuro-prompt-failure)

(ert-deftest kuro-prompt-status--all-faces-defined ()
  "Invariant: all prompt-status faces are defined."
  (dolist (entry kuro-prompt-status-test--face-exists-table)
    (pcase-let ((`(,_name ,face-sym) entry))
      (should (facep face-sym)))))

(ert-deftest kuro-prompt-status--defcustom-annotations-default-t ()
  "kuro-prompt-status-annotations defaults to t."
  (should (eq (default-value 'kuro-prompt-status-annotations) t)))

(provide 'kuro-prompt-status-test)

;;; kuro-prompt-status-test.el ends here
