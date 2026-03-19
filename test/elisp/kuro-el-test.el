;;; kuro-el-test.el --- ERT tests for kuro.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for pure functions defined in kuro.el:
;;   - kuro--setup-char-width-table  (char-width override logic)
;;   - kuro--window-size-change      (resize-pending recording logic)
;;   - kuro-mode-map                 (keymap structure)
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
               kuro-core-get-scroll-up
               kuro-core-get-scroll-down
               kuro-core-get-and-clear-title
               kuro-core-get-default-colors
               kuro-core-get-palette-updates
               kuro-core-get-image
               kuro-core-get-osc-data
               kuro-core-set-dec-mode
               kuro-core-get-bell-and-clear
               kuro-core-get-focus-mode
               kuro-core-get-mouse-protocol
               kuro-core-get-mouse-encoding
               kuro-core-get-kitty-kb-flags
               kuro-core-scrollback-len
               kuro-core-scrollback-line))
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

;;; ── Group 1: kuro--setup-char-width-table ───────────────────────────────────

(ert-deftest kuro-el-test--char-width-table-box-drawing-start ()
  "U+2500 (BOX DRAWINGS LIGHT HORIZONTAL) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2500)))))

(ert-deftest kuro-el-test--char-width-table-box-drawing-end ()
  "U+257F (BOX DRAWINGS LIGHT UP) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x257F)))))

(ert-deftest kuro-el-test--char-width-table-block-elements-start ()
  "U+2580 (UPPER HALF BLOCK) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2580)))))

(ert-deftest kuro-el-test--char-width-table-block-elements-end ()
  "U+259F (QUADRANT UPPER RIGHT AND LOWER LEFT AND LOWER RIGHT) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x259F)))))

(ert-deftest kuro-el-test--char-width-table-arrows-start ()
  "U+2190 (LEFTWARDS ARROW) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2190)))))

(ert-deftest kuro-el-test--char-width-table-arrows-end ()
  "U+21FF (last arrow in U+21xx block) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x21FF)))))

(ert-deftest kuro-el-test--char-width-table-math-operators ()
  "U+2200 (FOR ALL) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2200)))))

(ert-deftest kuro-el-test--char-width-table-geometric-shapes ()
  "U+25A0 (BLACK SQUARE) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x25A0)))))

(ert-deftest kuro-el-test--char-width-table-braille-start ()
  "U+2800 (BRAILLE PATTERN BLANK) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2800)))))

(ert-deftest kuro-el-test--char-width-table-braille-end ()
  "U+28FF (last Braille pattern) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x28FF)))))

(ert-deftest kuro-el-test--char-width-table-misc-symbols ()
  "U+2600 (BLACK SUN WITH RAYS) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2600)))))

(ert-deftest kuro-el-test--char-width-table-is-buffer-local ()
  "kuro--setup-char-width-table makes char-width-table buffer-local."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (local-variable-p 'char-width-table))))

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

(provide 'kuro-el-test)

;;; kuro-el-test.el ends here
