;;; kuro-navigation-test.el --- Tests for kuro-navigation  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-navigation.el prompt navigation functions.
;; Tests kuro-previous-prompt and kuro-next-prompt using mock
;; kuro--prompt-positions data.  No Rust module required.
;;
;; Data format: kuro--prompt-positions is a list of (MARK-TYPE ROW COL EXIT-CODE)
;; proper lists where MARK-TYPE is a string such as "prompt-start", ROW and COL
;; are 0-based integers, and EXIT-CODE is an integer or nil.  Matches the FFI
;; output of kuro-core-poll-prompt-marks.
;; Navigation compares ROW (cadr entry) against (1- (line-number-at-pos)).
;;
;; Group 5 covers kuro--update-prompt-positions (moved from
;; kuro-ffi-osc-test.el in Round 20 restructure).

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Load the module under test.  kuro-navigation requires kuro-ffi and
;; kuro-ffi-modes at load time; stub the declares so the file loads without
;; the Rust dynamic module.
(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--get-focus-events)
  (defalias 'kuro--get-focus-events (lambda () nil)))

(require 'kuro-navigation)

;;; Helpers

(defmacro kuro-nav-test--with-prompts (positions &rest body)
  "Run BODY in a temp buffer with `kuro--prompt-positions' set to POSITIONS.
The buffer starts with N+1 newlines so that line numbers map predictably:
line-number-at-pos at point-min returns 1, so cur-line = 0.
Each `forward-line N' places point at line N+1, cur-line = N."
  (declare (indent 1))
  `(with-temp-buffer
     ;; Insert enough lines so forward-line never goes out of range.
     (dotimes (_ 30) (insert "\n"))
     (goto-char (point-min))
     (setq-local kuro--prompt-positions ,positions)
     ,@body))

;;; Group 1: kuro-previous-prompt basic navigation

(ert-deftest kuro-navigation--previous-prompt-basic ()
  "kuro-previous-prompt moves point to the most recent prompt-start before cursor."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 2 0)
            '("prompt-start" 5 0)
            '("prompt-start" 9 0))
    ;; Place cursor at row 7 (forward-line 7 from point-min puts us at line 8,
    ;; so cur-line = 7).
    (forward-line 7)
    (kuro-previous-prompt)
    ;; The last prompt-start before row 7 is row 5.
    ;; After navigation: goto-char point-min + forward-line 5 = line 6.
    (should (= (line-number-at-pos) 6))))

(ert-deftest kuro-navigation--previous-prompt-picks-nearest ()
  "kuro-previous-prompt picks the closest (highest ROW) prompt-start before cursor."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 1 0)
            '("prompt-start" 3 0)
            '("prompt-start" 6 0))
    (forward-line 8)   ; cur-line = 8
    (kuro-previous-prompt)
    ;; Nearest prompt-start before 8 is row 6 → line 7.
    (should (= (line-number-at-pos) 7))))

(ert-deftest kuro-navigation--previous-prompt-skips-non-prompt-start ()
  "kuro-previous-prompt ignores entries that are not prompt-start."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 2 0)
            '("prompt-end" 4 0)
            '("command-start" 6 0)
            '("command-end" 8 0))
    (forward-line 10)  ; cur-line = 10
    (kuro-previous-prompt)
    ;; Only row 2 has mark-type prompt-start → line 3.
    (should (= (line-number-at-pos) 3))))

(ert-deftest kuro-navigation--previous-prompt-at-first-prompt-no-op ()
  "kuro-previous-prompt at or before the first prompt emits a message, no crash."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 5 0))
    ;; cur-line = 2, prompt is at row 5 (after cursor) → no candidate.
    (forward-line 2)
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) messages))))
        (kuro-previous-prompt))
      (should (equal messages '("kuro: no previous prompt"))))))

;;; Group 2: kuro-next-prompt basic navigation

(ert-deftest kuro-navigation--next-prompt-basic ()
  "kuro-next-prompt moves point to the first prompt-start after the cursor."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 2 0)
            '("prompt-start" 5 0)
            '("prompt-start" 9 0))
    (forward-line 3)   ; cur-line = 3
    (kuro-next-prompt)
    ;; First prompt-start after row 3 is row 5 → line 6.
    (should (= (line-number-at-pos) 6))))

(ert-deftest kuro-navigation--next-prompt-picks-nearest ()
  "kuro-next-prompt picks the smallest ROW greater than cur-line."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 4 0)
            '("prompt-start" 8 0)
            '("prompt-start" 12 0))
    (forward-line 5)   ; cur-line = 5
    (kuro-next-prompt)
    ;; First prompt-start after 5 is row 8 → line 9.
    (should (= (line-number-at-pos) 9))))

(ert-deftest kuro-navigation--next-prompt-skips-non-prompt-start ()
  "kuro-next-prompt ignores entries that are not prompt-start."
  (kuro-nav-test--with-prompts
      (list '("prompt-end" 3 0)
            '("command-start" 5 0)
            '("prompt-start" 7 0))
    (forward-line 1)   ; cur-line = 1
    (kuro-next-prompt)
    ;; Only row 7 has mark-type prompt-start → line 8.
    (should (= (line-number-at-pos) 8))))

(ert-deftest kuro-navigation--next-prompt-at-last-prompt-no-op ()
  "kuro-next-prompt past the last prompt emits a message, no crash."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 3 0))
    (forward-line 5)   ; cur-line = 5, prompt at row 3 (before cursor)
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) messages))))
        (kuro-next-prompt))
      (should (equal messages '("kuro: no next prompt"))))))

;;; Group 3: No prompts

(ert-deftest kuro-navigation--no-prompts-previous ()
  "kuro-previous-prompt with empty prompt list emits message, no crash."
  (kuro-nav-test--with-prompts
      nil
    (forward-line 5)
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) messages))))
        (kuro-previous-prompt))
      (should (equal messages '("kuro: no previous prompt"))))))

(ert-deftest kuro-navigation--no-prompts-next ()
  "kuro-next-prompt with empty prompt list emits message, no crash."
  (kuro-nav-test--with-prompts
      nil
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) messages))))
        (kuro-next-prompt))
      (should (equal messages '("kuro: no next prompt"))))))

;;; Group 4: Edge cases

(ert-deftest kuro-navigation--previous-excludes-same-row ()
  "kuro-previous-prompt excludes a prompt at exactly cur-line (must be strictly <)."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 3 0)
            '("prompt-start" 6 0))
    (forward-line 6)   ; cur-line = 6, prompt at row 6 is NOT < 6
    (kuro-previous-prompt)
    ;; Only row 3 qualifies → line 4.
    (should (= (line-number-at-pos) 4))))

(ert-deftest kuro-navigation--next-excludes-same-row ()
  "kuro-next-prompt excludes a prompt at exactly cur-line (must be strictly >)."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 4 0)
            '("prompt-start" 8 0))
    (forward-line 4)   ; cur-line = 4, prompt at row 4 is NOT > 4
    (kuro-next-prompt)
    ;; Only row 8 qualifies → line 9.
    (should (= (line-number-at-pos) 9))))

(ert-deftest kuro-navigation--prompt-positions-is-buffer-local ()
  "kuro--prompt-positions is buffer-local (isolated per buffer)."
  (let ((buf1 (get-buffer-create " *kuro-nav-test-1*"))
        (buf2 (get-buffer-create " *kuro-nav-test-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1
            (setq-local kuro--prompt-positions (list '("prompt-start" 3 0))))
          (with-current-buffer buf2
            (setq-local kuro--prompt-positions nil))
          (should (equal (with-current-buffer buf1 kuro--prompt-positions)
                         (list '("prompt-start" 3 0))))
          (should (null (with-current-buffer buf2 kuro--prompt-positions))))
      (kill-buffer buf1)
      (kill-buffer buf2))))

(ert-deftest kuro-navigation--multiple-mark-types-coexist ()
  "Navigation works correctly when multiple mark types are present."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 1 0)
            '("prompt-end" 2 0)
            '("command-start" 3 0)
            '("command-end" 4 0)
            '("prompt-start" 5 0)
            '("prompt-end" 6 0))
    (forward-line 3)  ; cur-line = 3
    ;; Previous prompt-start before row 3 is row 1 → line 2.
    (kuro-previous-prompt)
    (should (= (line-number-at-pos) 2))))

;;; Group 5: kuro--update-prompt-positions

(ert-deftest kuro-navigation--update-prompt-positions-sorts-by-row ()
  "Marks should be sorted ascending by row number (cadr of each mark)."
  (let* ((mark-a '("prompt-end" 5 0))
         (mark-b '("prompt-start" 3 0))
         (result (kuro--update-prompt-positions (list mark-a mark-b) nil 100)))
    ;; After sorting, row 3 must come before row 5
    (should (= (cadr (nth 0 result)) 3))
    (should (= (cadr (nth 1 result)) 5))))

(ert-deftest kuro-navigation--update-prompt-positions-caps-at-max ()
  "Result length must not exceed max-count."
  (let ((marks (mapcar (lambda (n) (list "prompt-start" n 0))
                       (number-sequence 0 9))))
    (let ((result (kuro--update-prompt-positions marks nil 3)))
      (should (= (length result) 3)))))

(ert-deftest kuro-navigation--update-prompt-positions-merges-with-existing ()
  "New marks are merged with existing positions; total is both combined."
  (let* ((existing '(("prompt-start" 1 0)))
         (new-marks '(("prompt-end" 2 0)))
         (result (kuro--update-prompt-positions new-marks existing 100)))
    (should (= (length result) 2))))

(ert-deftest kuro-navigation--update-prompt-positions-empty-marks-returns-existing ()
  "Empty marks list returns existing positions (sorted, unchanged)."
  (let* ((existing '(("prompt-start" 1 0)))
         (result (kuro--update-prompt-positions nil existing 100)))
    (should (equal result existing))))

(ert-deftest kuro-navigation--update-prompt-positions-empty-existing-works ()
  "Empty existing positions with non-empty marks returns sorted marks."
  (let* ((marks '(("prompt-start" 7 0) ("prompt-end" 2 0)))
         (result (kuro--update-prompt-positions marks nil 100)))
    (should (= (length result) 2))
    (should (= (cadr (nth 0 result)) 2))
    (should (= (cadr (nth 1 result)) 7))))

(ert-deftest kuro-navigation--update-prompt-positions-max-count-zero-returns-empty ()
  "max-count=0 returns empty list regardless of marks."
  (let ((marks '(("prompt-start" 1 0) ("prompt-end" 2 0)))
        (existing '(("prompt-start" 0 0))))
    (let ((result (kuro--update-prompt-positions marks existing 0)))
      (should (null result)))))

(ert-deftest kuro-navigation--update-prompt-positions-sorted-and-capped ()
  "Combined marks+existing are sorted by row and then capped at max-count."
  ;; 5 existing + 5 new = 10 combined; cap at 4 (lowest rows kept by sort+take)
  (let* ((existing (mapcar (lambda (n) (list "prompt-start" (* n 2) 0))
                           (number-sequence 0 4))) ; rows 0,2,4,6,8
         (new-marks (mapcar (lambda (n) (list "prompt-end" (1+ (* n 2)) 0))
                            (number-sequence 0 4))) ; rows 1,3,5,7,9
         (result (kuro--update-prompt-positions new-marks existing 4)))
    (should (= (length result) 4))
    ;; First 4 sorted rows are 0,1,2,3
    (should (= (cadr (nth 0 result)) 0))
    (should (= (cadr (nth 1 result)) 1))
    (should (= (cadr (nth 2 result)) 2))
    (should (= (cadr (nth 3 result)) 3))))

;;; Group 6: Focus event handlers (kuro--handle-focus-in, kuro--handle-focus-out)
;;
;; kuro--handle-focus-in and kuro--handle-focus-out both guard on three conditions:
;;   1. (derived-mode-p 'kuro-mode) — buffer must be in kuro-mode
;;   2. kuro--initialized — session must be active
;;   3. (kuro--get-focus-events) — focus tracking mode must be enabled
;; When any guard fails the function is a no-op (sends nothing).

(defmacro kuro-nav-test--with-focus-stubs (initialized focus-on sent-var &rest body)
  "Run BODY with focus-handler stubs in place.
INITIALIZED and FOCUS-ON control the guard predicates.
SENT-VAR names a variable that receives the string passed to `kuro--send-key'."
  (declare (indent 3))
  `(let ((kuro--initialized ,initialized)
         (,sent-var nil))
     (cl-letf (((symbol-function 'derived-mode-p)        (lambda (&rest _) t))
               ((symbol-function 'kuro--get-focus-events) (lambda () ,focus-on))
               ((symbol-function 'kuro--send-key)         (lambda (s) (setq ,sent-var s))))
       ,@body)))

(ert-deftest kuro-navigation--handle-focus-in-noop-when-not-initialized ()
  "kuro--handle-focus-in does nothing when kuro--initialized is nil."
  (kuro-nav-test--with-focus-stubs nil t sent
    (kuro--handle-focus-in)
    (should-not sent)))

(ert-deftest kuro-navigation--handle-focus-in-noop-when-focus-tracking-off ()
  "kuro--handle-focus-in does nothing when focus-tracking mode is disabled."
  (kuro-nav-test--with-focus-stubs t nil sent
    (kuro--handle-focus-in)
    (should-not sent)))

(ert-deftest kuro-navigation--handle-focus-in-sends-escape-sequence ()
  "kuro--handle-focus-in sends ESC [ I when initialized and focus-tracking is on."
  (kuro-nav-test--with-focus-stubs t t sent
    (kuro--handle-focus-in)
    (should (equal sent "\e[I"))))

(ert-deftest kuro-navigation--handle-focus-out-noop-when-not-initialized ()
  "kuro--handle-focus-out does nothing when kuro--initialized is nil."
  (kuro-nav-test--with-focus-stubs nil t sent
    (kuro--handle-focus-out)
    (should-not sent)))

(ert-deftest kuro-navigation--handle-focus-out-noop-when-focus-tracking-off ()
  "kuro--handle-focus-out does nothing when focus-tracking mode is disabled."
  (kuro-nav-test--with-focus-stubs t nil sent
    (kuro--handle-focus-out)
    (should-not sent)))

(ert-deftest kuro-navigation--handle-focus-out-sends-escape-sequence ()
  "kuro--handle-focus-out sends ESC [ O when initialized and focus-tracking is on."
  (kuro-nav-test--with-focus-stubs t t sent
    (kuro--handle-focus-out)
    (should (equal sent "\e[O"))))

(provide 'kuro-navigation-test)
;;; kuro-navigation-test.el ends here
