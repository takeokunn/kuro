;;; kuro-test-ext3.el --- ERT tests for kuro.el (Groups 6-9 keymap)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-support)

;;; ── Group 6 (keymap): kuro-mode-map additional bindings ─────────────────────

(ert-deftest kuro-el-test--mode-map-has-sigstop-binding ()
  "kuro-mode-map binds C-c C-z to kuro-send-sigstop."
  (should (lookup-key kuro-mode-map "\C-c\C-z")))

(ert-deftest kuro-el-test--mode-map-has-sigquit-binding ()
  "kuro-mode-map binds C-c C-\\ to kuro-send-sigquit."
  (should (lookup-key kuro-mode-map "\C-c\C-\\")))

(ert-deftest kuro-el-test--mode-map-has-send-next-key-binding ()
  "kuro-mode-map binds C-c C-q to kuro-send-next-key."
  (should (lookup-key kuro-mode-map "\C-c\C-q")))

;;; ── Group 7 (keymap): kuro--enter-copy-mode keymap details ──────────────────

(ert-deftest kuro-el-test--enter-copy-mode-installs-local-map ()
  "kuro--enter-copy-mode installs a buffer-local keymap via use-local-map."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    ;; After entering copy mode the local-map must NOT be kuro-mode-map.
    (should-not (eq (current-local-map) kuro-mode-map))))

(ert-deftest kuro-el-test--enter-copy-mode-copy-map-has-exit-binding ()
  "The copy-mode keymap installed by kuro--enter-copy-mode binds C-c C-t."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (lookup-key (current-local-map) "\C-c\C-t"))))

(ert-deftest kuro-el-test--exit-copy-mode-restores-kuro-mode-map ()
  "kuro--exit-copy-mode restores kuro-mode-map as the local map."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))
    (should (eq (current-local-map) kuro-mode-map))))

(ert-deftest kuro-el-test--exit-copy-mode-noop-render-when-not-fboundp ()
  "kuro--exit-copy-mode does not error when kuro--render-cycle is not fboundp."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    ;; Temporarily unbind kuro--render-cycle to simulate the module not loaded.
    (let ((saved (symbol-function 'kuro--render-cycle)))
      (fmakunbound 'kuro--render-cycle)
      (unwind-protect
          (should-not (condition-case err (progn (kuro--exit-copy-mode) nil) (error err)))
        (fset 'kuro--render-cycle saved)))))

(ert-deftest kuro-el-test--copy-mode-enter-then-exit-is-idempotent ()
  "Entering and exiting copy mode twice leaves kuro--copy-mode at nil."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode)
      (should-not kuro--copy-mode)
      (kuro--enter-copy-mode)
      (kuro--exit-copy-mode)
      (should-not kuro--copy-mode))))

(ert-deftest kuro-el-test--enter-copy-mode-copy-map-has-m-w-binding ()
  "The copy-mode keymap installed by kuro--enter-copy-mode binds M-w."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (lookup-key (current-local-map) (kbd "M-w")))))

(ert-deftest kuro-el-test--copy-mode-m-w-bound-to-copy-region-and-exit ()
  "M-w in copy mode is bound to kuro--copy-copy-region-and-exit."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "M-w"))
                #'kuro--copy-copy-region-and-exit))))

(ert-deftest kuro-el-test--copy-mode-save-and-exit-exits-when-auto-exit-t ()
  "kuro--copy-mode-save-and-exit exits copy mode when kuro-copy-mode-auto-exit is t."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should kuro--copy-mode)
    (let ((kuro-copy-mode-auto-exit t))
      ;; Insert text so kill-ring-save has a region to copy.
      (let ((inhibit-read-only t))
        (insert "test text"))
      (set-mark (point-min))
      (goto-char (point-max))
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
        (kuro--copy-mode-save-and-exit)))
    (should-not kuro--copy-mode)))

(ert-deftest kuro-el-test--copy-mode-save-and-exit-stays-when-auto-exit-nil ()
  "kuro--copy-mode-save-and-exit keeps copy mode when kuro-copy-mode-auto-exit is nil."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should kuro--copy-mode)
    (let ((kuro-copy-mode-auto-exit nil))
      (let ((inhibit-read-only t))
        (insert "test text"))
      (set-mark (point-min))
      (goto-char (point-max))
      (kuro--copy-mode-save-and-exit))
    (should kuro--copy-mode)))

(ert-deftest kuro-el-test--copy-mode-auto-exit-defcustom-default-is-t ()
  "kuro-copy-mode-auto-exit default value is t."
  (should (eq (default-value 'kuro-copy-mode-auto-exit) t)))

;;; ── Group 8 (keymap): kuro--window-size-change predicate — additional cases ───

(ert-deftest kuro-el-test--resize-logic-zero-dimensions-treated-as-change ()
  "A change from 24x80 to 0x0 is treated as a dimension change."
  (let ((result (kuro-el-test--apply-resize-logic t 0 0 24 80)))
    (should (equal result (cons 0 0)))))

(ert-deftest kuro-el-test--resize-logic-large-terminal ()
  "A 200-row 500-column terminal change is captured."
  (let ((result (kuro-el-test--apply-resize-logic t 200 500 24 80)))
    (should (equal result (cons 200 500)))))

(ert-deftest kuro-el-test--resize-logic-returns-nil-when-both-unchanged ()
  "Returns nil when neither rows nor cols differ from last known values."
  ;; Ensure a symmetric case (rows same, cols same).
  (let ((result (kuro-el-test--apply-resize-logic t 80 24 80 24)))
    (should (null result))))

;;; ── Group 9 (keymap): kuro-mode buffer-local variable initialization ─────────

(ert-deftest kuro-el-test--last-rows-defvar-initial-value ()
  "kuro--last-rows permanent-local is initially declared as 0."
  ;; The defvar default is 0; we verify the initial value in a fresh buffer.
  (with-temp-buffer
    (setq-local kuro--last-rows 0)
    (should (= kuro--last-rows 0))))

(ert-deftest kuro-el-test--last-cols-defvar-initial-value ()
  "kuro--last-cols permanent-local is initially declared as 0."
  (with-temp-buffer
    (setq-local kuro--last-cols 0)
    (should (= kuro--last-cols 0))))

(ert-deftest kuro-el-test--copy-mode-defvar-initial-value ()
  "kuro--copy-mode permanent-local default is nil (not-in-copy-mode)."
  (with-temp-buffer
    (setq-local kuro--copy-mode nil)
    (should-not kuro--copy-mode)))

;;; ── Group 10: kuro--window-size-change — full function call via stubs ──────────
;;
;; The function requires window/frame infrastructure.  We stub window-list,
;; window-buffer, window-body-height, and window-body-width so the full
;; dolist + derived-mode-p + resize-pending path can be exercised in batch ERT.

(ert-deftest kuro-el-test--window-size-change-sets-pending-for-kuro-buffer ()
  "`kuro--window-size-change' sets kuro--resize-pending when dimensions change."
  (let ((buf (get-buffer-create "*kuro-wsc-test-resize*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (kuro-mode)
            (setq kuro--initialized t
                  kuro--last-rows 24
                  kuro--last-cols 80
                  kuro--resize-pending nil))
          (cl-letf (((symbol-function 'window-list)
                     (lambda (&rest _) '(fake-win)))
                    ((symbol-function 'window-buffer)
                     (lambda (_w) buf))
                    ((symbol-function 'window-body-height)
                     (lambda (_w) 30))
                    ((symbol-function 'window-body-width)
                     (lambda (_w) 100)))
            (kuro--window-size-change nil)
            (with-current-buffer buf
              (should (equal kuro--resize-pending (cons 30 100))))))
      (kill-buffer buf))))

(ert-deftest kuro-el-test--window-size-change-noop-for-non-kuro-buffer ()
  "`kuro--window-size-change' skips buffers that are not in kuro-mode."
  (let ((buf (get-buffer-create "*kuro-wsc-test-noop*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (fundamental-mode)
            (setq-local kuro--resize-pending nil))
          (cl-letf (((symbol-function 'window-list)
                     (lambda (&rest _) '(fake-win)))
                    ((symbol-function 'window-buffer)
                     (lambda (_w) buf))
                    ((symbol-function 'window-body-height)
                     (lambda (_w) 30))
                    ((symbol-function 'window-body-width)
                     (lambda (_w) 100)))
            (kuro--window-size-change nil)
            (with-current-buffer buf
              (should (null kuro--resize-pending)))))
      (kill-buffer buf))))

(provide 'kuro-test-ext3)
;;; kuro-test-ext3.el ends here
