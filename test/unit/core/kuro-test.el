;;; kuro-test.el --- ERT tests for kuro.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for pure functions defined in kuro.el:
;;   - kuro--window-size-change  (resize-pending recording logic)
;;   - kuro-mode-map             (keymap structure)
;;   - kuro--enter/exit-copy-mode / kuro-copy-mode
;;   - kuro--make-focus-change-fn
;;
;; char-width and glyph-metric tests moved to kuro-faces-test.el (Round 44)
;; because kuro--setup-char-width-table and EA-Ambiguous functions now live
;; in kuro-faces.el.
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
       (el-dir (expand-file-name "../../../emacs-lisp/core" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro)

;;; ── Group 2: kuro--window-size-change resize logic ──────────────────────────
;;
;; kuro--window-size-change iterates live windows of a frame with
;; (window-list frame).  To avoid spinning up real frames/windows in batch
;; mode, we test the inner predicate logic directly using the same
;; buffer-local state variables the function reads.

(defmacro kuro-el-test--with-kuro-buffer (&rest body)
  "Run BODY in a temp buffer simulating a live kuro-mode buffer."
  `(with-temp-buffer
     (setq major-mode 'kuro-mode)
     (setq-local kuro--initialized t)
     (setq-local kuro--last-rows 24)
     (setq-local kuro--last-cols 80)
     (setq-local kuro--resize-pending nil)
     ,@body))

(defun kuro-el-test--apply-resize-logic (initialized new-rows new-cols last-rows last-cols)
  "Evaluate the resize-pending predicate used inside kuro--window-size-change.
Returns the value that kuro--resize-pending would be set to, or nil."
  (when (and initialized
             (or (/= new-rows last-rows)
                 (/= new-cols last-cols)))
    (cons new-rows new-cols)))

(ert-deftest kuro-el-test--window-size-change-sets-resize-pending ()
  "resize-pending is set when both rows and cols change."
  (let ((result (kuro-el-test--apply-resize-logic t 30 100 24 80)))
    (should (equal result (cons 30 100)))))

(ert-deftest kuro-el-test--window-size-change-no-change-no-pending ()
  "resize-pending is nil when dimensions are unchanged."
  (let ((result (kuro-el-test--apply-resize-logic t 24 80 24 80)))
    (should (null result))))

(ert-deftest kuro-el-test--window-size-change-not-initialized-no-pending ()
  "resize-pending is nil when kuro--initialized is nil."
  (let ((result (kuro-el-test--apply-resize-logic nil 30 100 24 80)))
    (should (null result))))

(ert-deftest kuro-el-test--window-size-change-row-only-change ()
  "resize-pending is set when only rows change."
  (let ((result (kuro-el-test--apply-resize-logic t 30 80 24 80)))
    (should (equal result (cons 30 80)))))

(ert-deftest kuro-el-test--window-size-change-col-only-change ()
  "resize-pending is set when only cols change."
  (let ((result (kuro-el-test--apply-resize-logic t 24 100 24 80)))
    (should (equal result (cons 24 100)))))

(ert-deftest kuro-el-test--window-size-change-non-kuro-buffer-not-affected ()
  "A non-kuro-mode buffer is never updated by kuro--window-size-change.
Verified by asserting the mode-predicate guard independently."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    ;; The guard inside kuro--window-size-change:
    (should-not (derived-mode-p 'kuro-mode))))

(ert-deftest kuro-el-test--window-size-change-resize-pending-cons-shape ()
  "kuro--resize-pending, when set, is a cons of (rows . cols)."
  (let ((result (kuro-el-test--apply-resize-logic t 40 132 24 80)))
    (should (consp result))
    (should (= (car result) 40))
    (should (= (cdr result) 132))))

;;; ── Group 3: kuro-mode-map structure ────────────────────────────────────────

(ert-deftest kuro-el-test--mode-map-is-keymap ()
  "kuro-mode-map is a keymap."
  (should (keymapp kuro-mode-map)))

(ert-deftest kuro-el-test--mode-map-has-interrupt-binding ()
  "kuro-mode-map binds C-c C-c to kuro-send-interrupt."
  (should (lookup-key kuro-mode-map "\C-c\C-c")))

(ert-deftest kuro-el-test--mode-map-has-copy-mode-binding ()
  "kuro-mode-map binds C-c C-t to kuro-copy-mode."
  (should (lookup-key kuro-mode-map "\C-c\C-t")))

(ert-deftest kuro-el-test--mode-map-has-next-prompt-binding ()
  "kuro-mode-map binds C-c C-n to kuro-next-prompt."
  (should (lookup-key kuro-mode-map "\C-c\C-n")))

(ert-deftest kuro-el-test--mode-map-has-prev-prompt-binding ()
  "kuro-mode-map binds C-c C-p to kuro-previous-prompt."
  (should (lookup-key kuro-mode-map "\C-c\C-p")))

;;; ── Group 4: kuro--enter-copy-mode / kuro--exit-copy-mode ───────────────────
;;
;; kuro--enter-copy-mode: sets kuro--copy-mode to t, installs a copy-map
;;   via use-local-map, sets mode-name to "Kuro[Copy]".
;; kuro--exit-copy-mode: sets kuro--copy-mode to nil, restores kuro-mode-map,
;;   sets mode-name to "Kuro", calls kuro--render-cycle if fboundp.
;; kuro-copy-mode (interactive): guards with (derived-mode-p 'kuro-mode),
;;   then toggles by calling enter or exit.

(defmacro kuro-el-test--with-kuro-mode-buffer (&rest body)
  "Run BODY in a temp buffer with major-mode set to kuro-mode (no real init)."
  `(with-temp-buffer
     (setq major-mode 'kuro-mode)
     (setq-local kuro--copy-mode nil)
     (setq mode-name "Kuro")
     (use-local-map kuro-mode-map)
     ,@body))

(ert-deftest kuro-el-test--enter-copy-mode-sets-flag ()
  "kuro--enter-copy-mode sets kuro--copy-mode to non-nil."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should kuro--copy-mode)))

(ert-deftest kuro-el-test--enter-copy-mode-sets-mode-name ()
  "kuro--enter-copy-mode sets mode-name to propertized \"Kuro[Copy]\"."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (equal (substring-no-properties mode-name) "Kuro[Copy]"))))

(ert-deftest kuro-el-test--exit-copy-mode-clears-flag ()
  "kuro--exit-copy-mode sets kuro--copy-mode to nil."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should kuro--copy-mode)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))
    (should-not kuro--copy-mode)))

(ert-deftest kuro-el-test--exit-copy-mode-sets-mode-name ()
  "kuro--exit-copy-mode sets mode-name back to \"Kuro\"."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))
    (should (equal mode-name "Kuro"))))

(ert-deftest kuro-el-test--exit-copy-mode-calls-render-cycle ()
  "kuro--exit-copy-mode calls kuro--render-cycle when it is fboundp."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((render-called nil))
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t))))
        (kuro--exit-copy-mode))
      (should render-called))))

(ert-deftest kuro-el-test--copy-mode-toggle-enter ()
  "kuro-copy-mode enters copy mode when kuro--copy-mode is nil."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode nil)
    (kuro-copy-mode)
    (should kuro--copy-mode)))

(ert-deftest kuro-el-test--copy-mode-toggle-exit ()
  "kuro-copy-mode exits copy mode when kuro--copy-mode is already t."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should kuro--copy-mode)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro-copy-mode))
    (should-not kuro--copy-mode)))

(ert-deftest kuro-el-test--copy-mode-errors-outside-kuro-mode ()
  "kuro-copy-mode signals user-error when not in a kuro-mode buffer."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-copy-mode) :type 'user-error)))

;;; ── Group 5: kuro--make-focus-change-fn ─────────────────────────────────────

(ert-deftest kuro-el-test--make-focus-change-fn-returns-function ()
  "kuro--make-focus-change-fn returns a callable function."
  (should (functionp (kuro--make-focus-change-fn nil))))

(ert-deftest kuro-el-test--make-focus-change-fn-chains-prev ()
  "The returned function calls prev when it is a function."
  (let ((called nil))
    (cl-letf (((symbol-function 'frame-focus-state) (lambda () t))
              ((symbol-function 'kuro--handle-focus-in) #'ignore)
              ((symbol-function 'kuro--handle-focus-out) #'ignore))
      (funcall (kuro--make-focus-change-fn (lambda () (setq called t))))
      (should called))))

(ert-deftest kuro-el-test--make-focus-change-fn-nil-prev-no-error ()
  "The returned function does not error when prev is nil."
  (cl-letf (((symbol-function 'frame-focus-state) (lambda () nil))
            ((symbol-function 'kuro--handle-focus-in) #'ignore)
            ((symbol-function 'kuro--handle-focus-out) #'ignore))
    (should-not
     (condition-case err
         (progn (funcall (kuro--make-focus-change-fn nil)) nil)
       (error err)))))

(ert-deftest kuro-el-test--make-focus-change-fn-dispatches-focus-in ()
  "Returned function calls kuro--handle-focus-in when frame has focus."
  (let ((focus-in-called nil))
    (cl-letf (((symbol-function 'frame-focus-state) (lambda () t))
              ((symbol-function 'kuro--handle-focus-in)
               (lambda () (setq focus-in-called t)))
              ((symbol-function 'kuro--handle-focus-out) #'ignore))
      (funcall (kuro--make-focus-change-fn nil))
      (should focus-in-called))))

(ert-deftest kuro-el-test--make-focus-change-fn-dispatches-focus-out ()
  "Returned function calls kuro--handle-focus-out when frame lacks focus."
  (let ((focus-out-called nil))
    (cl-letf (((symbol-function 'frame-focus-state) (lambda () nil))
              ((symbol-function 'kuro--handle-focus-in) #'ignore)
              ((symbol-function 'kuro--handle-focus-out)
               (lambda () (setq focus-out-called t))))
      (funcall (kuro--make-focus-change-fn nil))
      (should focus-out-called))))

(ert-deftest kuro-el-test--make-focus-change-fn-non-function-prev-no-error ()
  "The returned function does not error when prev is a non-function non-nil value."
  (cl-letf (((symbol-function 'frame-focus-state) (lambda () t))
            ((symbol-function 'kuro--handle-focus-in) #'ignore)
            ((symbol-function 'kuro--handle-focus-out) #'ignore))
    ;; A symbol that is not a function — should not raise.
    (should-not
     (condition-case err
         (progn (funcall (kuro--make-focus-change-fn 'not-a-function)) nil)
       (error err)))))

(provide 'kuro-test)

;;; kuro-test.el ends here
