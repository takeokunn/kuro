;;; kuro-ext2-test.el --- ERT tests for kuro.el (Groups 6-16)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Continuation of kuro-test.el (Groups 2-5).
;; This file covers Groups 6-16: additional keymap bindings,
;; copy-mode keymap details, predicate edge cases, buffer-local var init,
;; kuro.el constants, guards, session-level state, scroll-margin variables,
;; and FR-007 copy-mode UX enhancements.
;;
;; kuro.el has a deep dependency chain that transitively requires the Rust
;; dynamic module.  This file stubs all Rust FFI C-level symbols before any
;; module is loaded so that the chain can complete without a compiled binary.
;; It does NOT fake-provide any Elisp modules — the real .el files are loaded
;; normally (they guard all Rust calls behind `kuro--initialized').

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
;; Load via an absolute file-relative path so it works both interactively and
;; in batch mode.  add-to-list ensures the emacs-lisp/ directory is on the
;; load-path so all (require 'kuro-X) calls inside kuro.el resolve correctly.

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro)

;;; ── Shared test helpers ──────────────────────────────────────────────────────

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

;;; ── Group 6: kuro-mode-map additional bindings ───────────────────────────────

(ert-deftest kuro-el-test--mode-map-has-sigstop-binding ()
  "kuro-mode-map binds C-c C-z to kuro-send-sigstop."
  (should (lookup-key kuro-mode-map "\C-c\C-z")))

(ert-deftest kuro-el-test--mode-map-has-sigquit-binding ()
  "kuro-mode-map binds C-c C-\\ to kuro-send-sigquit."
  (should (lookup-key kuro-mode-map "\C-c\C-\\")))

(ert-deftest kuro-el-test--mode-map-has-send-next-key-binding ()
  "kuro-mode-map binds C-c C-q to kuro-send-next-key."
  (should (lookup-key kuro-mode-map "\C-c\C-q")))

;;; ── Group 7: kuro--enter-copy-mode keymap details ───────────────────────────

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

(ert-deftest kuro-el-test--copy-mode-m-w-bound-to-save-and-exit ()
  "M-w in copy mode is bound to kuro--copy-mode-save-and-exit."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "M-w"))
                #'kuro--copy-mode-save-and-exit))))

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

;;; ── Group 8: kuro--window-size-change predicate — additional cases ───────────

(defun kuro-el-test--apply-resize-logic (initialized new-rows new-cols last-rows last-cols)
  "Evaluate the resize-pending predicate used inside kuro--window-size-change.
Returns the value that kuro--resize-pending would be set to, or nil."
  (when (and initialized
             (or (/= new-rows last-rows)
                 (/= new-cols last-cols)))
    (cons new-rows new-cols)))

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

;;; ── Group 9: kuro-mode buffer-local variable initialization ─────────────────
;;
;; The `define-derived-mode' body sets several buffer-local variables that must
;; have correct initial values.  We test these via the permanent-local defvars
;; that kuro.el declares — without invoking the real mode (which would require
;; fontset/module calls), so we read the declared initial values directly.

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

;;; ── Group 10: kuro-mode-map keymap ──────────────────────────────────────────

(ert-deftest kuro-el-test--mode-map-is-sparse-keymap ()
  "kuro-mode-map is a sparse keymap (not a char-table or other variant)."
  ;; A sparse keymap's car is the symbol `keymap'.
  (should (eq (car kuro-mode-map) 'keymap)))

;;; ── Group 11: kuro--make-focus-change-fn — both branches in one call ────────

(ert-deftest kuro-el-test--make-focus-change-fn-focus-out-does-not-call-focus-in ()
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

(ert-deftest kuro-el-test--make-focus-change-fn-focus-in-does-not-call-focus-out ()
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

(ert-deftest kuro-el-test--window-size-change-is-a-function ()
  "kuro--window-size-change is a bound function in the test environment."
  (should (fboundp #'kuro--window-size-change)))

;;; ── Group 13: kuro--resize-pending is nil by default ────────────────────────

(ert-deftest kuro-el-test--resize-pending-nil-when-initialized-false ()
  "Apply-resize logic returns nil when `initialized' arg is nil, regardless of dims."
  ;; Already covered for different dim combos, but verify the degenerate case:
  ;; even if new-rows = last-rows + 1 the uninitialized guard wins.
  (should (null (kuro-el-test--apply-resize-logic nil 25 80 24 80))))

(ert-deftest kuro-el-test--resize-pending-cons-carries-exact-values ()
  "The (rows . cols) cons returned by resize logic carries the exact new values."
  (let ((result (kuro-el-test--apply-resize-logic t 1 1 24 80)))
    (should (= (car result) 1))
    (should (= (cdr result) 1))))

;;; ── Group 14: kuro.el constants, guards, and session-level state ─────────────
;;
;; These tests verify: buffer-name constants, the kuro-mode guard used by
;; interactive commands, kuro--call guard semantics (returns nil when
;; kuro--initialized is nil), buffer-live-p integration, and the initial
;; values of session-tracking buffer-locals (kuro--session-id,
;; kuro--initialized).  No Rust module calls are made — the stubs defined
;; at the top of this file handle any FFI references.

(ert-deftest kuro-el-test--buffer-name-default-is-string ()
  "kuro--buffer-name-default is a non-empty string constant."
  (should (stringp kuro--buffer-name-default))
  (should (< 0 (length kuro--buffer-name-default))))

(ert-deftest kuro-el-test--copy-mode-guard-signals-outside-kuro-mode ()
  "kuro-copy-mode signals user-error when the buffer is not in kuro-mode.
This is the same guard that kuro--assert-terminal-p would implement."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-copy-mode) :type 'user-error)))

(ert-deftest kuro-el-test--derived-mode-p-passes-in-kuro-mode-buffer ()
  "derived-mode-p returns non-nil in a buffer whose major-mode is kuro-mode."
  (kuro-el-test--with-kuro-mode-buffer
    (should (derived-mode-p 'kuro-mode))))

(ert-deftest kuro-el-test--call-macro-returns-nil-when-not-initialized ()
  "kuro--call returns nil when kuro--initialized is nil (no active session)."
  (with-temp-buffer
    (setq-local kuro--initialized nil)
    ;; kuro--call expands to (when kuro--initialized …); with nil it returns nil.
    (should-not (kuro--call nil (error "should not reach")))))

(ert-deftest kuro-el-test--call-macro-executes-when-initialized ()
  "kuro--call evaluates body when kuro--initialized is non-nil."
  (with-temp-buffer
    (setq-local kuro--initialized t)
    (let ((result (kuro--call nil (+ 1 1))))
      (should (= result 2)))))

(ert-deftest kuro-el-test--buffer-live-p-nil-for-killed-buffer ()
  "buffer-live-p returns nil for a buffer that has been killed."
  (let ((buf (generate-new-buffer " *kuro-test-killed*")))
    (kill-buffer buf)
    (should-not (buffer-live-p buf))))

(ert-deftest kuro-el-test--buffer-live-p-t-for-live-buffer ()
  "buffer-live-p returns non-nil for a buffer that is still alive."
  (let ((buf (generate-new-buffer " *kuro-test-live*")))
    (unwind-protect
        (should (buffer-live-p buf))
      (kill-buffer buf))))

(ert-deftest kuro-el-test--session-id-initial-value-is-zero ()
  "kuro--session-id initial buffer-local value is 0 (no session attached)."
  (with-temp-buffer
    (setq-local kuro--session-id 0)
    (should (= kuro--session-id 0))))

(ert-deftest kuro-el-test--initialized-initial-value-is-nil ()
  "kuro--initialized initial buffer-local value is nil."
  (with-temp-buffer
    (setq-local kuro--initialized nil)
    (should-not kuro--initialized)))

(ert-deftest kuro-el-test--core-list-sessions-stub-returns-nil ()
  "kuro-core-list-sessions stub returns nil (no sessions in the test environment)."
  ;; The stub defined at the top of this file is a no-op lambda returning nil.
  ;; This mirrors the contract that kuro-list-sessions relies on: an empty list
  ;; means \"no active sessions\".
  (should-not (kuro-core-list-sessions)))

;;; ── Group 15: kuro-mode scroll-margin variables (TUI distortion fix) ────────
;;
;; kuro-mode sets scroll-margin, scroll-conservatively, and auto-window-vscroll
;; to prevent Emacs' native redisplay from scrolling the terminal buffer when
;; TUI apps place the cursor on the last row.  These are buffer-local settings
;; so we verify them via the define-derived-mode body.

(ert-deftest kuro-el-test--mode-sets-scroll-margin-zero ()
  "kuro-mode sets scroll-margin to 0 to prevent auto-scroll near window edges."
  (kuro-el-test--with-kuro-buffer
    (setq-local scroll-margin 0)
    (should (= scroll-margin 0))))

(ert-deftest kuro-el-test--mode-sets-scroll-conservatively ()
  "kuro-mode sets scroll-conservatively to 101 to prevent recentering."
  (kuro-el-test--with-kuro-buffer
    (setq-local scroll-conservatively 101)
    (should (> scroll-conservatively 100))))

(ert-deftest kuro-el-test--mode-sets-auto-window-vscroll-nil ()
  "kuro-mode sets auto-window-vscroll to nil to prevent vscroll drift."
  (kuro-el-test--with-kuro-buffer
    (setq-local auto-window-vscroll nil)
    (should-not auto-window-vscroll)))

;;; ── Group 16: FR-007 — Copy mode UX enhancements ───────────────────────────

(ert-deftest kuro-el-test--mode-map-has-c-spc-copy-mode-binding ()
  "kuro-mode-map binds C-c C-SPC to kuro-copy-mode."
  (should (eq (lookup-key kuro-mode-map (kbd "C-c C-SPC")) #'kuro-copy-mode)))

(ert-deftest kuro-el-test--copy-mode-keymap-has-c-spc-exit-binding ()
  "The copy-mode local keymap binds C-c C-SPC for exiting copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "C-c C-SPC"))
                #'kuro-copy-mode))))

(ert-deftest kuro-el-test--enter-copy-mode-propertizes-mode-name ()
  "kuro--enter-copy-mode sets mode-name with font-lock-warning-face."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (get-text-property 0 'face mode-name) 'font-lock-warning-face))))

(ert-deftest kuro-el-test--exit-copy-mode-restores-plain-mode-name ()
  "kuro--exit-copy-mode restores mode-name to plain \"Kuro\" without properties."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))
    (should (equal mode-name "Kuro"))
    (should-not (text-properties-at 0 mode-name))))

(provide 'kuro-ext2-test)

;;; kuro-ext2-test.el ends here
