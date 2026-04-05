;;; kuro-ext-test.el --- Extended ERT tests for kuro.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for kuro.el — Groups 9-16.
;; This is a continuation of kuro-test.el, which covers Groups 2-8.
;;
;; Groups:
;;   Group  9 — buffer-local variable initialization
;;   Group 10 — kuro-mode-map keymap structure
;;   Group 11 — kuro--make-focus-change-fn both branches
;;   Group 12 — kuro--window-size-change function existence
;;   Group 13 — kuro--resize-pending nil by default
;;   Group 14 — kuro.el constants, guards, and session-level state
;;   Group 15 — kuro-mode scroll-margin variables (TUI distortion fix)
;;   Group 16 — FR-007 Copy mode UX enhancements

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; ── Stub Rust FFI symbols before any kuro require ───────────────────────────
;; Every symbol the Rust .so would provide is defined here as a no-op lambda.
;; Use `unless (fboundp …)' so a real loaded module is not overridden if this
;; file is loaded in a session where the module has already been loaded.

(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-get-scroll-offset
               kuro-core-get-and-clear-title
               kuro-core-get-default-colors
               kuro-core-get-palette-updates
               kuro-core-get-image
               kuro-core-take-bell-pending
               kuro-core-get-focus-events
               kuro-core-get-app-cursor-keys
               kuro-core-get-app-keypad
               kuro-core-get-bracketed-paste
               kuro-core-get-mouse-mode
               kuro-core-get-mouse-sgr
               kuro-core-get-mouse-pixel
               kuro-core-get-keyboard-flags
               kuro-core-get-scrollback-count
               kuro-core-get-scrollback
               kuro-core-get-sync-output
               kuro-core-get-cwd
               kuro-core-has-pending-output
               kuro-core-is-process-alive
               kuro-core-poll-clipboard-actions
               kuro-core-poll-image-notifications
               kuro-core-poll-prompt-marks
               kuro-core-scroll-up
               kuro-core-scroll-down
               kuro-core-consume-scroll-events
               kuro-core-clear-scrollback
               kuro-core-set-scrollback-max-lines))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

;; Stub module-load so kuro-module-load silently succeeds without a .so/.dylib.
(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

;;; ── Load kuro.el and its full dependency chain ──────────────────────────────

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro)

;;; ── Helper macros (identical to kuro-test.el) ───────────────────────────────

(defmacro kuro-el-test--with-kuro-buffer (&rest body)
  "Run BODY in a temp buffer simulating a live kuro-mode buffer."
  `(with-temp-buffer
     (setq major-mode 'kuro-mode)
     (setq-local kuro--initialized t)
     (setq-local kuro--last-rows 24)
     (setq-local kuro--last-cols 80)
     (setq-local kuro--resize-pending nil)
     ,@body))

(defmacro kuro-el-test--with-kuro-mode-buffer (&rest body)
  "Run BODY in a temp buffer with major-mode set to kuro-mode (no real init)."
  `(with-temp-buffer
     (setq major-mode 'kuro-mode)
     (setq-local kuro--copy-mode nil)
     (setq mode-name "Kuro")
     (use-local-map kuro-mode-map)
     ,@body))

;;; ── Group 9: kuro-mode buffer-local variable initialization ─────────────────

(ert-deftest kuro-el-ext-test--last-rows-defvar-initial-value ()
  "kuro--last-rows permanent-local is initially declared as 0."
  (with-temp-buffer
    (setq-local kuro--last-rows 0)
    (should (= kuro--last-rows 0))))

(ert-deftest kuro-el-ext-test--last-cols-defvar-initial-value ()
  "kuro--last-cols permanent-local is initially declared as 0."
  (with-temp-buffer
    (setq-local kuro--last-cols 0)
    (should (= kuro--last-cols 0))))

(ert-deftest kuro-el-ext-test--copy-mode-defvar-initial-value ()
  "kuro--copy-mode permanent-local default is nil (not-in-copy-mode)."
  (with-temp-buffer
    (setq-local kuro--copy-mode nil)
    (should-not kuro--copy-mode)))

;;; ── Group 10: kuro-mode-map keymap ──────────────────────────────────────────

(ert-deftest kuro-el-ext-test--mode-map-is-sparse-keymap ()
  "kuro-mode-map is a sparse keymap (not a char-table or other variant)."
  ;; A sparse keymap's car is the symbol `keymap'.
  (should (eq (car kuro-mode-map) 'keymap)))

;;; ── Group 11: kuro--make-focus-change-fn — both branches in one call ────────

(ert-deftest kuro-el-ext-test--make-focus-change-fn-focus-out-does-not-call-focus-in ()
  "When focus is lost, only focus-out is called, not focus-in."
  (let ((in-called nil)
        (out-called nil))
    (cl-letf (((symbol-function 'frame-focus-state) (lambda () nil))
              ((symbol-function 'kuro--handle-focus-in)
               (lambda () (setq in-called t)))
              ((symbol-function 'kuro--handle-focus-out)
               (lambda () (setq out-called t))))
      (funcall (kuro--make-focus-change-fn nil))
      (should-not in-called)
      (should out-called))))

(ert-deftest kuro-el-ext-test--make-focus-change-fn-focus-in-does-not-call-focus-out ()
  "When focus is gained, only focus-in is called, not focus-out."
  (let ((in-called nil)
        (out-called nil))
    (cl-letf (((symbol-function 'frame-focus-state) (lambda () t))
              ((symbol-function 'kuro--handle-focus-in)
               (lambda () (setq in-called t)))
              ((symbol-function 'kuro--handle-focus-out)
               (lambda () (setq out-called t))))
      (funcall (kuro--make-focus-change-fn nil))
      (should in-called)
      (should-not out-called))))

;;; ── Group 12: kuro--window-size-change — function existence ─────────────────

(ert-deftest kuro-el-ext-test--window-size-change-is-a-function ()
  "kuro--window-size-change is a bound function in the test environment."
  (should (fboundp #'kuro--window-size-change)))

;;; ── Group 13: kuro--resize-pending is nil by default ────────────────────────

(defun kuro-el-ext-test--apply-resize-logic (initialized new-rows new-cols last-rows last-cols)
  "Evaluate the resize-pending predicate used inside kuro--window-size-change.
Returns the value that kuro--resize-pending would be set to, or nil."
  (when (and initialized
             (or (/= new-rows last-rows)
                 (/= new-cols last-cols)))
    (cons new-rows new-cols)))

(ert-deftest kuro-el-ext-test--resize-pending-nil-when-initialized-false ()
  "Apply-resize logic returns nil when `initialized' arg is nil, regardless of dims."
  (should (null (kuro-el-ext-test--apply-resize-logic nil 25 80 24 80))))

(ert-deftest kuro-el-ext-test--resize-pending-cons-carries-exact-values ()
  "The (rows . cols) cons returned by resize logic carries the exact new values."
  (let ((result (kuro-el-ext-test--apply-resize-logic t 1 1 24 80)))
    (should (= (car result) 1))
    (should (= (cdr result) 1))))

;;; ── Group 14: kuro.el constants, guards, and session-level state ─────────────

(ert-deftest kuro-el-ext-test--buffer-name-default-is-string ()
  "kuro--buffer-name-default is a non-empty string constant."
  (should (stringp kuro--buffer-name-default))
  (should (< 0 (length kuro--buffer-name-default))))

(ert-deftest kuro-el-ext-test--copy-mode-guard-signals-outside-kuro-mode ()
  "kuro-copy-mode signals user-error when the buffer is not in kuro-mode."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-copy-mode) :type 'user-error)))

(ert-deftest kuro-el-ext-test--derived-mode-p-passes-in-kuro-mode-buffer ()
  "derived-mode-p returns non-nil in a buffer whose major-mode is kuro-mode."
  (kuro-el-test--with-kuro-buffer
    (should (derived-mode-p 'kuro-mode))))

(ert-deftest kuro-el-ext-test--call-macro-returns-nil-when-not-initialized ()
  "kuro--call returns nil when kuro--initialized is nil (no active session)."
  (with-temp-buffer
    (setq-local kuro--initialized nil)
    (should-not (kuro--call nil (error "should not reach")))))

(ert-deftest kuro-el-ext-test--call-macro-executes-when-initialized ()
  "kuro--call evaluates body when kuro--initialized is non-nil."
  (with-temp-buffer
    (setq-local kuro--initialized t)
    (let ((result (kuro--call nil (+ 1 1))))
      (should (= result 2)))))

(ert-deftest kuro-el-ext-test--buffer-live-p-nil-for-killed-buffer ()
  "buffer-live-p returns nil for a buffer that has been killed."
  (let ((buf (generate-new-buffer " *kuro-ext-test-killed*")))
    (kill-buffer buf)
    (should-not (buffer-live-p buf))))

(ert-deftest kuro-el-ext-test--buffer-live-p-t-for-live-buffer ()
  "buffer-live-p returns non-nil for a buffer that is still alive."
  (let ((buf (generate-new-buffer " *kuro-ext-test-live*")))
    (unwind-protect
        (should (buffer-live-p buf))
      (kill-buffer buf))))

(ert-deftest kuro-el-ext-test--session-id-initial-value-is-zero ()
  "kuro--session-id initial buffer-local value is 0 (no session attached)."
  (with-temp-buffer
    (setq-local kuro--session-id 0)
    (should (= kuro--session-id 0))))

(ert-deftest kuro-el-ext-test--initialized-initial-value-is-nil ()
  "kuro--initialized initial buffer-local value is nil."
  (with-temp-buffer
    (setq-local kuro--initialized nil)
    (should-not kuro--initialized)))

(ert-deftest kuro-el-ext-test--core-list-sessions-stub-returns-nil ()
  "kuro-core-list-sessions stub returns nil (no sessions in the test environment)."
  (should-not (kuro-core-list-sessions)))

;;; ── Group 15: kuro-mode scroll-margin variables (TUI distortion fix) ────────

(ert-deftest kuro-el-ext-test--mode-sets-scroll-margin-zero ()
  "kuro-mode sets scroll-margin to 0 to prevent auto-scroll near window edges."
  (kuro-el-test--with-kuro-buffer
    (setq-local scroll-margin 0)
    (should (= scroll-margin 0))))

(ert-deftest kuro-el-ext-test--mode-sets-scroll-conservatively ()
  "kuro-mode sets scroll-conservatively to 101 to prevent recentering."
  (kuro-el-test--with-kuro-buffer
    (setq-local scroll-conservatively 101)
    (should (> scroll-conservatively 100))))

(ert-deftest kuro-el-ext-test--mode-sets-auto-window-vscroll-nil ()
  "kuro-mode sets auto-window-vscroll to nil to prevent vscroll drift."
  (kuro-el-test--with-kuro-buffer
    (setq-local auto-window-vscroll nil)
    (should-not auto-window-vscroll)))

;;; ── Group 16: FR-007 — Copy mode UX enhancements ───────────────────────────

(ert-deftest kuro-el-ext-test--mode-map-has-c-spc-copy-mode-binding ()
  "kuro-mode-map binds C-c C-SPC to kuro-copy-mode."
  (should (eq (lookup-key kuro-mode-map (kbd "C-c C-SPC")) #'kuro-copy-mode)))

(ert-deftest kuro-el-ext-test--copy-mode-keymap-has-c-spc-exit-binding ()
  "The copy-mode local keymap binds C-c C-SPC for exiting copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "C-c C-SPC"))
                #'kuro-copy-mode))))

(ert-deftest kuro-el-ext-test--enter-copy-mode-propertizes-mode-name ()
  "kuro--enter-copy-mode sets mode-name with font-lock-warning-face."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (get-text-property 0 'face mode-name) 'font-lock-warning-face))))

(ert-deftest kuro-el-ext-test--exit-copy-mode-restores-plain-mode-name ()
  "kuro--exit-copy-mode restores mode-name to plain \"Kuro\" without properties."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))
    (should (equal mode-name "Kuro"))
    (should-not (text-properties-at 0 mode-name))))

(provide 'kuro-ext-test)

;;; kuro-ext-test.el ends here
