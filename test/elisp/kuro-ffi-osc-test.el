;;; kuro-ffi-osc-test.el --- Unit tests for kuro-ffi-osc.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-ffi-osc.el (OSC event wrappers and helpers).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; Only kuro--update-prompt-positions is tested here — it is a pure
;; list-processing function with no FFI calls or buffer-local state.
;; NOTE: kuro--update-prompt-positions was moved to kuro-navigation.el
;; (Round 16 FR-E5); this test file now loads kuro-navigation to find it.
;;
;; Mark structure: each mark is a proper list (MARK-TYPE ROW COL)
;; where MARK-TYPE is a string like "prompt-start",
;; ROW and COL are integers.  This matches the output of
;; kuro_core_poll_prompt_marks in rust-core/src/ffi/bridge/events.rs.
;;
;; Covered:
;;   - kuro--update-prompt-positions: sorts by row ascending (cadr)
;;   - kuro--update-prompt-positions: caps result at max-count
;;   - kuro--update-prompt-positions: merges new marks with existing positions
;;   - kuro--update-prompt-positions: empty marks returns existing positions (sorted)
;;   - kuro--update-prompt-positions: empty existing positions works correctly
;;   - kuro--update-prompt-positions: max-count=0 returns empty list
;;   - kuro--update-prompt-positions: marks and positions together, sorted correctly

;;; Code:

(require 'ert)
(require 'seq)

;; Stub the Rust FFI functions that kuro-ffi-osc.el's (require 'kuro-ffi) would need.
;; These must be defined BEFORE loading kuro-ffi-osc.el.
(unless (fboundp 'kuro-core-get-and-clear-title)
  (fset 'kuro-core-get-and-clear-title (lambda () nil)))
(unless (fboundp 'kuro-core-get-cwd)
  (fset 'kuro-core-get-cwd (lambda () nil)))
(unless (fboundp 'kuro-core-poll-clipboard-actions)
  (fset 'kuro-core-poll-clipboard-actions (lambda () nil)))
(unless (fboundp 'kuro-core-poll-prompt-marks)
  (fset 'kuro-core-poll-prompt-marks (lambda () nil)))
(unless (fboundp 'kuro-core-get-image)
  (fset 'kuro-core-get-image (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-image-notifications)
  (fset 'kuro-core-poll-image-notifications (lambda () nil)))
(unless (fboundp 'kuro-core-consume-scroll-events)
  (fset 'kuro-core-consume-scroll-events (lambda () nil)))
(unless (fboundp 'kuro-core-has-pending-output)
  (fset 'kuro-core-has-pending-output (lambda () nil)))
(unless (fboundp 'kuro-core-get-palette-updates)
  (fset 'kuro-core-get-palette-updates (lambda () nil)))
(unless (fboundp 'kuro-core-get-default-colors)
  (fset 'kuro-core-get-default-colors (lambda () nil)))
(unless (fboundp 'kuro-core-get-scrollback)
  (fset 'kuro-core-get-scrollback (lambda (_n) nil)))
(unless (fboundp 'kuro-core-clear-scrollback)
  (fset 'kuro-core-clear-scrollback (lambda () nil)))
(unless (fboundp 'kuro-core-set-scrollback-max-lines)
  (fset 'kuro-core-set-scrollback-max-lines (lambda (_n) nil)))
(unless (fboundp 'kuro-core-get-scrollback-count)
  (fset 'kuro-core-get-scrollback-count (lambda () 0)))
(unless (fboundp 'kuro-core-scroll-up)
  (fset 'kuro-core-scroll-up (lambda (_n) nil)))
(unless (fboundp 'kuro-core-scroll-down)
  (fset 'kuro-core-scroll-down (lambda (_n) nil)))
(unless (fboundp 'kuro-core-get-scroll-offset)
  (fset 'kuro-core-get-scroll-offset (lambda () 0)))

;; Also stub kuro-core-init and other functions required transitively.
(unless (fboundp 'kuro-core-init)
  (fset 'kuro-core-init (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-resize)
  (fset 'kuro-core-resize (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-send-key)
  (fset 'kuro-core-send-key (lambda (&rest _) nil)))
(unless (fboundp 'kuro-core-poll-updates)
  (fset 'kuro-core-poll-updates (lambda () nil)))
(unless (fboundp 'kuro-core-poll-updates-with-faces)
  (fset 'kuro-core-poll-updates-with-faces (lambda () nil)))
(unless (fboundp 'kuro-core-get-cursor)
  (fset 'kuro-core-get-cursor (lambda () nil)))
(unless (fboundp 'kuro-core-is-cursor-visible)
  (fset 'kuro-core-is-cursor-visible (lambda () t)))
(unless (fboundp 'kuro-core-get-cursor-shape)
  (fset 'kuro-core-get-cursor-shape (lambda () 0)))
(unless (fboundp 'kuro-core-get-mouse-tracking-mode)
  (fset 'kuro-core-get-mouse-tracking-mode (lambda () nil)))
(unless (fboundp 'kuro-core-get-bracketed-paste)
  (fset 'kuro-core-get-bracketed-paste (lambda () nil)))
(unless (fboundp 'kuro-core-is-alt-screen-active)
  (fset 'kuro-core-is-alt-screen-active (lambda () nil)))
(unless (fboundp 'kuro-core-get-focus-tracking)
  (fset 'kuro-core-get-focus-tracking (lambda () nil)))
(unless (fboundp 'kuro-core-get-kitty-kb-flags)
  (fset 'kuro-core-get-kitty-kb-flags (lambda () 0)))
(unless (fboundp 'kuro-core-get-sync-update-active)
  (fset 'kuro-core-get-sync-update-active (lambda () nil)))
(unless (fboundp 'kuro-core-shutdown)
  (fset 'kuro-core-shutdown (lambda () nil)))

;; Stub kuro-ffi-modes functions required transitively by kuro-navigation.el.
(unless (fboundp 'kuro-core-get-app-cursor-keys)
  (fset 'kuro-core-get-app-cursor-keys (lambda () nil)))
(unless (fboundp 'kuro-core-get-focus-events)
  (fset 'kuro-core-get-focus-events (lambda () nil)))

;; Stub defcustom variables that kuro-config.el would normally define.
(defvar kuro--initialized nil)

(require 'kuro-ffi-osc)
(require 'kuro-navigation)

;;; Tests for kuro--update-prompt-positions
;;
;; Mark structure: (MARK-TYPE ROW COL)
;;   (car mark)  = mark-type string (e.g. "prompt-start")
;;   (cadr mark) = row integer
;;   (caddr mark) = col integer

(ert-deftest kuro-ffi-osc-test--update-prompt-positions-sorts-by-row ()
  "Marks should be sorted ascending by row number (cadr of each mark)."
  (let* ((mark-a '("prompt-end" 5 0))
         (mark-b '("prompt-start" 3 0))
         (result (kuro--update-prompt-positions (list mark-a mark-b) nil 100)))
    ;; After sorting, row 3 must come before row 5
    (should (= (cadr (nth 0 result)) 3))
    (should (= (cadr (nth 1 result)) 5))))

(ert-deftest kuro-ffi-osc-test--update-prompt-positions-caps-at-max ()
  "Result length must not exceed max-count."
  (let ((marks (mapcar (lambda (n) (list "prompt-start" n 0))
                       (number-sequence 0 9))))
    (let ((result (kuro--update-prompt-positions marks nil 3)))
      (should (= (length result) 3)))))

(ert-deftest kuro-ffi-osc-test--update-prompt-positions-merges-with-existing ()
  "New marks are merged with existing positions; total is both combined."
  (let* ((existing '(("prompt-start" 1 0)))
         (new-marks '(("prompt-end" 2 0)))
         (result (kuro--update-prompt-positions new-marks existing 100)))
    (should (= (length result) 2))))

(ert-deftest kuro-ffi-osc-test--update-prompt-positions-empty-marks-returns-existing ()
  "Empty marks list returns existing positions (sorted, unchanged)."
  (let* ((existing '(("prompt-start" 1 0)))
         (result (kuro--update-prompt-positions nil existing 100)))
    (should (equal result existing))))

(ert-deftest kuro-ffi-osc-test--update-prompt-positions-empty-existing-works ()
  "Empty existing positions with non-empty marks returns sorted marks."
  (let* ((marks '(("prompt-start" 7 0) ("prompt-end" 2 0)))
         (result (kuro--update-prompt-positions marks nil 100)))
    (should (= (length result) 2))
    (should (= (cadr (nth 0 result)) 2))
    (should (= (cadr (nth 1 result)) 7))))

(ert-deftest kuro-ffi-osc-test--update-prompt-positions-max-count-zero-returns-empty ()
  "max-count=0 returns empty list regardless of marks."
  (let ((marks '(("prompt-start" 1 0) ("prompt-end" 2 0)))
        (existing '(("prompt-start" 0 0))))
    (let ((result (kuro--update-prompt-positions marks existing 0)))
      (should (null result)))))

(ert-deftest kuro-ffi-osc-test--update-prompt-positions-sorted-and-capped ()
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

(provide 'kuro-ffi-osc-test)

;;; kuro-ffi-osc-test.el ends here
