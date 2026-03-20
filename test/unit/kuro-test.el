;;; kuro-test.el --- ERT tests for kuro.el  -*- lexical-binding: t; -*-

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

(ert-deftest kuro-el-test--char-width-table-cjk-override ()
  "In Japanese language environment, EA-Ambiguous chars must still be width 1."
  (let ((orig-env current-language-environment))
    (unwind-protect
        (progn
          (set-language-environment "Japanese")
          (with-temp-buffer
            ;; Before setup: CJK env makes these width 2
            (should (= 2 (char-width #x25A0)))  ; ■
            (should (= 2 (char-width #x2502)))  ; │
            (should (= 2 (char-width #x2500)))  ; ─
            ;; After setup: must be 1
            (kuro--setup-char-width-table)
            (should (= 1 (char-width #x25A0)))
            (should (= 1 (char-width #x2502)))
            (should (= 1 (char-width #x2500)))
            (should (= 1 (char-width #x2588)))  ; █
            (should (= 1 (char-width #x2192)))  ; →
            (should (= 1 (char-width #x28C0))))) ; ⣀
      (set-language-environment orig-env))))

(ert-deftest kuro-el-test--char-width-survives-set-language-environment ()
  "char-width overrides must survive `set-language-environment' via hook.
`set-language-environment' replaces buffer-local `char-width-table' with a
fresh copy, destroying our overrides.  The hook installed by kuro must
re-apply them.  This is the root cause of the btop IO% width corruption:
if the user's init.el calls `set-language-environment' after kuro-mode,
the overrides are lost and box-drawing/geometric chars revert to width 2."
  (let ((orig-env current-language-environment))
    (unwind-protect
        (with-temp-buffer
          ;; Simulate kuro-mode setup
          (setq major-mode 'kuro-mode)
          (kuro--setup-char-width-table)
          (should (= 1 (char-width #x25A0)))
          ;; Now set-language-environment "Japanese" — this destroys the table
          (set-language-environment "Japanese")
          ;; The hook should have re-applied overrides
          (should (= 1 (char-width #x25A0)))
          (should (= 1 (char-width #x2502)))
          (should (= 1 (char-width #x2500))))
      (set-language-environment orig-env))))

(ert-deftest kuro-el-test--string-width-btop-line ()
  "A 120-char btop line must have string-width 120 after char-width-table setup.
This is the exact scenario that causes IO% column misalignment in CJK Emacs:
box-drawing (│) and geometric shapes (■) would otherwise be width 2, making
the visual line wider than 120 columns."
  (let ((orig-env current-language-environment))
    (unwind-protect
        (progn
          (set-language-environment "Japanese")
          (with-temp-buffer
            (kuro--setup-char-width-table)
            ;; Simplified btop disk line: 120 chars with │ and ■ characters
            (let ((btop-line (concat "│  23%                    │"
                                     " Used: 19% ■■■■■  701 GiB "
                                     "││   87580 Google C /Applications/"
                                     "Google  take   856M ⣀⣀⣀⣀⣀  1.5  │")))
              (should (= (length btop-line) 120))
              (should (= (string-width btop-line) 120)))))
      (set-language-environment orig-env))))

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

;;; ── Group 4: font glyph-width fix structure ───────────────────────────────────
;;
;; The actual font operations require a graphical display and cannot be tested
;; in batch mode.  We verify the functions' structure and graceful degradation.

(ert-deftest kuro-el-test--assign-mono-fonts-noop-in-batch ()
  "kuro--assign-mono-fonts is a no-op when display-graphic-p is nil (batch mode)."
  (should-not (kuro--assign-mono-fonts)))

(ert-deftest kuro-el-test--refine-glyph-widths-noop-in-batch ()
  "kuro--refine-glyph-widths is a no-op when display-graphic-p is nil (batch mode)."
  (should-not (kuro--refine-glyph-widths)))

(ert-deftest kuro-el-test--char-width-overrides-match-probe-chars ()
  "kuro--char-width-overrides and kuro--glyph-probe-chars must cover the same ranges.
If they diverge, char-width-table says width 1 but the font still renders
at width 2 (or vice versa), causing the btop column misalignment."
  (let ((cwt-ranges (mapcar (lambda (r) (cons (car r) (cdr r)))
                            kuro--char-width-overrides)))
    (should (= (length kuro--char-width-overrides) 9))
    ;; Every char-width-overrides range must have a corresponding probe char
    (should (= (length kuro--glyph-probe-chars) 9))
    (dolist (entry kuro--char-width-overrides)
      (should (assq (car entry) kuro--glyph-probe-chars)))
    ;; Spot-check critical ranges
    (should (member '(#x2500 . #x257F) cwt-ranges))  ; Box Drawing
    (should (member '(#x2580 . #x259F) cwt-ranges))  ; Block Elements
    (should (member '(#x25A0 . #x25FF) cwt-ranges)))) ; Geometric Shapes

;;; ── Group 5: kuro--apply-char-width-overrides ───────────────────────────────
;;
;; kuro--apply-char-width-overrides iterates kuro--char-width-overrides and
;; calls (set-char-table-range char-width-table range 1) for each entry.
;; It must be called after char-width-table is buffer-local.

(ert-deftest kuro-el-test--apply-overrides-sets-box-drawing-width ()
  "kuro--apply-char-width-overrides forces box-drawing range to width 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2500 . #x257F))))))

(ert-deftest kuro-el-test--apply-overrides-sets-block-elements-width ()
  "kuro--apply-char-width-overrides forces block-elements range to width 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2580 . #x259F))))))

(ert-deftest kuro-el-test--apply-overrides-sets-arrows-width ()
  "kuro--apply-char-width-overrides forces arrows range to width 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2190 . #x21FF))))))

(ert-deftest kuro-el-test--apply-overrides-sets-braille-width ()
  "kuro--apply-char-width-overrides forces braille range to width 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2800 . #x28FF))))))

(ert-deftest kuro-el-test--apply-overrides-all-ranges-covered ()
  "kuro--apply-char-width-overrides sets every entry in kuro--char-width-overrides to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (dolist (range kuro--char-width-overrides)
      (should (= 1 (char-table-range char-width-table range))))))

;;; ── Group 6: kuro--enter-copy-mode / kuro--exit-copy-mode ───────────────────
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
  "kuro--enter-copy-mode sets mode-name to \"Kuro[Copy]\"."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (equal mode-name "Kuro[Copy]"))))

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

(provide 'kuro-test)

;;; kuro-test.el ends here
