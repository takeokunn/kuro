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
(require 'cl-lib)

;; Stub FFI symbols so kuro-prompt-status loads without the Rust module.
(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-is-process-alive))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-prompt-status)

;;; Helpers

(defmacro kuro-prompt-status-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with prompt status state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--prompt-status-overlays nil)
           (kuro-prompt-status-annotations t)
           (kuro-prompt-status-success-indicator "✓")
           (kuro-prompt-status-failure-indicator "✗"))
       ,@body)))

;;; Group 1: kuro--prompt-status-indicator — return values

(ert-deftest kuro-prompt-status--indicator-nil-for-nil-exit-code ()
  "kuro--prompt-status-indicator returns nil when exit-code is nil."
  (should (null (kuro--prompt-status-indicator nil))))

(ert-deftest kuro-prompt-status--indicator-success-for-zero ()
  "kuro--prompt-status-indicator returns a propertized success string for exit 0."
  (let ((result (kuro--prompt-status-indicator 0)))
    (should (stringp result))
    (should (string= (substring-no-properties result) "✓"))
    (should (eq (get-text-property 0 'face result) 'kuro-prompt-success))))

(ert-deftest kuro-prompt-status--indicator-failure-for-nonzero ()
  "kuro--prompt-status-indicator returns a propertized failure string for non-zero exit."
  (let ((result (kuro--prompt-status-indicator 1)))
    (should (stringp result))
    (should (string= (substring-no-properties result) "✗"))
    (should (eq (get-text-property 0 'face result) 'kuro-prompt-failure))))

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

(ert-deftest kuro-prompt-status--format-duration-sub-second ()
  "Duration <1000ms renders as \"Nms\"."
  (should (equal (kuro--format-prompt-duration 250) "250ms")))

;;; Group 4c: kuro--format-prompt-duration — band boundary values

(ert-deftest kuro-prompt-status--format-duration-0ms ()
  "Lower edge of <1000 ms band: 0 renders as \"0ms\"."
  (should (equal (kuro--format-prompt-duration 0) "0ms")))

(ert-deftest kuro-prompt-status--format-duration-999ms ()
  "Upper edge of <1000 ms band: 999 renders as \"999ms\"."
  (should (equal (kuro--format-prompt-duration 999) "999ms")))

(ert-deftest kuro-prompt-status--format-duration-1000ms ()
  "Lower edge of <60000 ms band: 1000 renders as \"1.0s\"."
  (should (equal (kuro--format-prompt-duration 1000) "1.0s")))

(ert-deftest kuro-prompt-status--format-duration-59999ms ()
  "Upper edge of <60000 ms band: 59999 rounds via %.1f to \"60.0s\"."
  (should (equal (kuro--format-prompt-duration 59999) "60.0s")))

(ert-deftest kuro-prompt-status--format-duration-60000ms ()
  "Lower edge of MmSSs band: 60000 renders as \"1m00s\"."
  (should (equal (kuro--format-prompt-duration 60000) "1m00s")))

(ert-deftest kuro-prompt-status--format-duration-3600000ms ()
  "Hour mark in MmSSs band: 3,600,000 renders as \"60m00s\" (no hour rollover)."
  (should (equal (kuro--format-prompt-duration 3600000) "60m00s")))

;;; Group 5: kuro--ensure-left-margin — margin setup

(ert-deftest kuro-prompt-status--ensure-left-margin-sets-width ()
  "kuro--ensure-left-margin sets left-margin-width to 2 when unset."
  (with-temp-buffer
    (let ((kuro-prompt-status-annotations t)
          (left-margin-width nil))
      (kuro--ensure-left-margin)
      (should (= left-margin-width 2)))))

;;; Group 6: faces and defcustom defaults

(ert-deftest kuro-prompt-status--success-face-exists ()
  "kuro-prompt-success face is defined."
  (should (facep 'kuro-prompt-success)))

(ert-deftest kuro-prompt-status--failure-face-exists ()
  "kuro-prompt-failure face is defined."
  (should (facep 'kuro-prompt-failure)))

(ert-deftest kuro-prompt-status--defcustom-annotations-default-t ()
  "kuro-prompt-status-annotations defaults to t."
  (should (eq (default-value 'kuro-prompt-status-annotations) t)))

(provide 'kuro-prompt-status-test)

;;; kuro-prompt-status-test.el ends here
