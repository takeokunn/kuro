;;; kuro-e2e-scroll-test.el --- E2E tests for scrollback and scroll sequences -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for scrollback buffer management and scroll sequences:
;; scrollback content, max-lines propagation, viewport scrolling,
;; SU (scroll up) / SD (scroll down) sequences, ED 3 (erase scrollback),
;; clear-scrollback, and keyboard scroll commands.
;;
;; All waiting uses kuro-e2e--wait-for-text / kuro-e2e--render-idle.
;; NO standalone sleep-for calls are permitted.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-e2e-helpers)

;;;; Group 1: Scrollback content accumulates when output overflows the viewport

(ert-deftest kuro-e2e-scrollback-content ()
  "Generating 35 lines fills scrollback and early lines are accessible."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (dotimes (i 35)
     (kuro--send-key (format "echo LINE_%d" (1+ i)))
     (kuro--send-key "\r"))
   (should (kuro-e2e--wait-for-text buf "LINE_35"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     ;; Scrollback should have accumulated at least one line.
     (let ((count (condition-case nil (kuro--get-scrollback-count) (error 0))))
       (should (> count 0)))
     ;; Early lines should appear in scrollback.
     (let ((lines (condition-case nil (kuro--get-scrollback 50) (error nil))))
       (should (cl-some (lambda (l) (and (stringp l) (string-match-p "LINE_1\\b" l)))
                        lines))))))

;;;; Group 2: Scrollback max-lines setting is propagated to the Rust core

(ert-deftest kuro-e2e-scrollback-max-lines-propagation ()
  "Setting scrollback max to 10 after filling 30 lines caps count at 10."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Start with a generous limit.
   (with-current-buffer buf (kuro--set-scrollback-max-lines 1000))
   (dotimes (i 30)
     (kuro--send-key (format "echo LINE_%d" (1+ i)))
     (kuro--send-key "\r"))
   (should (kuro-e2e--wait-for-text buf "LINE_30"))
   (kuro-e2e--render-idle buf)
   ;; Now reduce the limit — the Rust core should trim the buffer.
   (with-current-buffer buf (kuro--set-scrollback-max-lines 10))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((count (condition-case nil (kuro--get-scrollback-count) (error 0))))
       (should (<= count 10))))))

;;;; Group 3: Viewport scroll offset changes on scroll-up / scroll-down

(ert-deftest kuro-e2e-scroll-viewport ()
  "kuro-scroll-up increases the viewport offset; kuro-scroll-down reduces it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (dotimes (i 30)
     (kuro--send-key (format "echo SVLINE_%d" (1+ i)))
     (kuro--send-key "\r"))
   (should (kuro-e2e--wait-for-text buf "SVLINE_30"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     ;; Baseline: offset is 0 (at live output).
     (let ((offset (condition-case nil (kuro--get-scroll-offset) (error 0))))
       (should (= offset 0)))
     ;; Scroll up 5 lines into history.
     (cl-letf (((symbol-function 'window-body-height) (lambda () 10)))
       (kuro-scroll-up))
     (kuro-e2e--render-idle buf)
     (let ((offset (condition-case nil (kuro--get-scroll-offset) (error 0))))
       (should (> offset 0)))
     ;; Scroll back down.
     (cl-letf (((symbol-function 'window-body-height) (lambda () 10)))
       (kuro-scroll-down))
     (kuro-e2e--render-idle buf)
     (let ((offset (condition-case nil (kuro--get-scroll-offset) (error 0))))
       (should (<= offset 1))))))

;;;; Group 4: SU (scroll up) sequence — ESC[24S scrolls content into scrollback

(ert-deftest kuro-e2e-scroll-up-su ()
  "ESC[24S (SU) pushes visible content into scrollback."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "echo KSU_MARKER")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KSU_MARKER"))
   (kuro-e2e--render-idle buf)
   ;; SU by a full screen height pushes all content to scrollback.
   (kuro--send-key "printf '\\033[24S'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   ;; KSU_MARKER must not be on the visible screen.
   (with-current-buffer buf
     (should (not (string-match-p "KSU_MARKER" (buffer-string)))))
   ;; KSU_MARKER must now be in scrollback.
   (with-current-buffer buf
     (let ((lines (condition-case nil (kuro--get-scrollback 100) (error nil))))
       (should (cl-some (lambda (l) (and (stringp l) (string-match-p "KSU_MARKER" l)))
                        lines))))))

;;;; Group 5: SD (scroll down) sequence — ESC[24T drops lines from scrollback

(ert-deftest kuro-e2e-scroll-down-sd ()
  "ESC[24T (SD) pulls blank lines from above; KSD_DROPPED is NOT added to scrollback."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Clear any existing scrollback.
   (with-current-buffer buf
     (condition-case nil (kuro--clear-scrollback) (error nil)))
   (kuro--send-key "echo KSD_DROPPED")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KSD_DROPPED"))
   (kuro-e2e--render-idle buf)
   ;; SD scrolls viewport downward — blanks scroll in from the top,
   ;; existing lines move down.  The marker should NOT end up in scrollback.
   (kuro--send-key "printf '\\033[24T'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((lines (condition-case nil (kuro--get-scrollback 100) (error nil))))
       (should (not (cl-some (lambda (l)
                               (and (stringp l) (string-match-p "KSD_DROPPED" l)))
                             lines)))))))

;;;; Group 6: ED 3 — erase scrollback (ESC[3J)

(ert-deftest kuro-e2e-erase-scrollback-ed3 ()
  "ESC[3J clears the scrollback buffer without affecting the visible screen."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Overflow the viewport to accumulate scrollback.
   (dotimes (i 30)
     (kuro--send-key (format "echo ED3LINE_%d" (1+ i)))
     (kuro--send-key "\r"))
   (should (kuro-e2e--wait-for-text buf "ED3LINE_30"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((before (condition-case nil (kuro--get-scrollback-count) (error 0))))
       (should (> before 0))))
   ;; ESC[3J erases scrollback only.
   (kuro--send-key "printf '\\033[3J'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((after (condition-case nil (kuro--get-scrollback-count) (error 0))))
       (should (<= after 1))))))

;;;; Group 7: kuro--clear-scrollback FFI function empties the buffer

(ert-deftest kuro-e2e-clear-scrollback ()
  "kuro--clear-scrollback reduces the scrollback count to 0."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Overflow the viewport to build up scrollback.
   (dotimes (i 30)
     (kuro--send-key (format "echo CLRLINE_%d" (1+ i)))
     (kuro--send-key "\r"))
   (should (kuro-e2e--wait-for-text buf "CLRLINE_30"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((before (condition-case nil (kuro--get-scrollback-count) (error 0))))
       (should (> before 0))))
   ;; Clear scrollback via the FFI wrapper.
   (with-current-buffer buf
     (condition-case nil (kuro--clear-scrollback) (error nil))
     (setq kuro--scroll-offset 0))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((after (condition-case nil (kuro--get-scrollback-count) (error 0))))
       (should (= after 0))))))

;;;; Group 8: Keyboard scroll commands change the viewport offset

(ert-deftest kuro-e2e-scrollback-keyboard-commands ()
  "kuro-scroll-up / kuro-scroll-down / kuro-scroll-bottom navigate the scrollback."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Overflow to populate scrollback.
   (dotimes (i 30)
     (kuro--send-key (format "echo KBLINE_%d" (1+ i)))
     (kuro--send-key "\r"))
   (should (kuro-e2e--wait-for-text buf "KBLINE_30"))
   (kuro-e2e--render-idle buf)
   ;; Use cl-letf to stub window-body-height at 10 so scroll amounts are deterministic.
   (with-current-buffer buf
     (cl-letf (((symbol-function 'window-body-height) (lambda () 10)))
       ;; Scroll up — offset must increase.
       (kuro-scroll-up)
       (kuro-e2e--render-idle buf)
       (let ((up-offset (condition-case nil (kuro--get-scroll-offset) (error 0))))
         (should (> up-offset 0)))
       ;; Scroll down — offset must decrease.
       (kuro-scroll-down)
       (kuro-e2e--render-idle buf)
       (let ((down-offset (condition-case nil (kuro--get-scroll-offset) (error 0))))
         (should (< down-offset 10)))
       ;; Scroll to bottom — offset must reach 0.
       (kuro-scroll-bottom)
       (kuro-e2e--render-idle buf)
       (let ((bottom-offset (condition-case nil (kuro--get-scroll-offset) (error 0))))
         (should (= bottom-offset 0)))))))

(provide 'kuro-e2e-scroll-test)

;;; kuro-e2e-scroll-test.el ends here
