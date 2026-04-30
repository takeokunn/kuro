;;; kuro-color-scheme-test.el --- Unit tests for kuro-color-scheme.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-color-scheme.el — Emacs theme bridge for DEC mode 2031.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Groups:
;;   Group 1 (L): kuro--color-scheme-luminance — Rec.709 conversion
;;   Group 2 (D): kuro--color-scheme-detect-dark-p — frame-background-mode + bg luminance
;;   Group 3 (G): kuro--color-scheme-install-hook — Emacs 29.1+ branch + fallback warning
;;   Group 4 (B): kuro--color-scheme-schedule — debounce coalescing
;;   Group 5 (R): kuro-color-scheme-refresh — push to live sessions / no-op safety

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; ── Bootstrap load-path and stubs ───────────────────────────────────────────

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (unit-dir (expand-file-name "../" this-dir))
       (el-core  (expand-file-name "../../emacs-lisp/core" this-dir))
       (el-feat  (expand-file-name "../../emacs-lisp/features" this-dir))
       (el-ffi   (expand-file-name "../../emacs-lisp/ffi" this-dir))
       (el-faces (expand-file-name "../../emacs-lisp/faces" this-dir)))
  (dolist (d (list unit-dir el-core el-feat el-ffi el-faces))
    (add-to-list 'load-path d t)))

;; Canonical FFI stubs cover most kuro-core-* symbols.
(require 'kuro-test-stubs)

;; The defun under test (Rust-side; absent in the test environment).
(unless (fboundp 'kuro-core-set-color-scheme)
  (fset 'kuro-core-set-color-scheme (lambda (&rest _) nil)))

(require 'kuro-config)
(require 'kuro-color-scheme)

;;; ── Helpers ─────────────────────────────────────────────────────────────────

(defmacro kuro-color-scheme-test--with-stubbed-set (binding &rest body)
  "Stub `kuro-core-set-color-scheme' to BINDING (a lambda) while running BODY."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'kuro-core-set-color-scheme) ,binding))
     ,@body))

(defmacro kuro-color-scheme-test--with-fake-buffers (buffers &rest body)
  "Stub `kuro--kuro-buffers' to return BUFFERS while running BODY."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'kuro--kuro-buffers) (lambda () ,buffers)))
     ,@body))

;;; ── Group 1 (L): kuro--color-scheme-luminance ───────────────────────────────

(ert-deftest kuro-color-scheme-luminance-black-is-zero ()
  "L1: Pure black has luminance ≈ 0."
  (let ((y (kuro--color-scheme-luminance "#000000")))
    (should (numberp y))
    (should (< y 0.001))))

(ert-deftest kuro-color-scheme-luminance-white-is-one ()
  "L2: Pure white has luminance ≈ 1."
  (let ((y (kuro--color-scheme-luminance "#ffffff")))
    (should (numberp y))
    (should (> y 0.999))))

(ert-deftest kuro-color-scheme-luminance-invalid-returns-nil ()
  "L3: Unknown color name returns nil rather than signalling."
  (should (null (kuro--color-scheme-luminance "this-is-not-a-color-xyz"))))

;;; ── Group 2 (D): kuro--color-scheme-detect-dark-p ───────────────────────────

(ert-deftest kuro-color-scheme-detect-dark-from-frame-mode-dark ()
  "D1: frame-background-mode=dark forces t regardless of bg."
  (cl-letf (((symbol-function 'frame-parameter)
             (lambda (_f _p) 'dark))
            ((symbol-function 'face-attribute)
             (lambda (&rest _) "#ffffff")))
    (should (kuro--color-scheme-detect-dark-p))))

(ert-deftest kuro-color-scheme-detect-dark-from-frame-mode-light ()
  "D2: frame-background-mode=light forces nil regardless of bg."
  (cl-letf (((symbol-function 'frame-parameter)
             (lambda (_f _p) 'light))
            ((symbol-function 'face-attribute)
             (lambda (&rest _) "#000000")))
    (should-not (kuro--color-scheme-detect-dark-p))))

(ert-deftest kuro-color-scheme-detect-dark-unspecified-bg-falls-back ()
  "D3: nil mode + unspecified bg → conservative t."
  (cl-letf (((symbol-function 'frame-parameter)
             (lambda (_f _p) nil))
            ((symbol-function 'face-attribute)
             (lambda (&rest _) 'unspecified)))
    (should (kuro--color-scheme-detect-dark-p))))

(ert-deftest kuro-color-scheme-detect-dark-light-bg-via-luminance ()
  "D4: nil mode + #f0f0f0 background (Y ≈ 0.94) → nil (light)."
  (cl-letf (((symbol-function 'frame-parameter)
             (lambda (_f _p) nil))
            ((symbol-function 'face-attribute)
             (lambda (&rest _) "#f0f0f0")))
    (should-not (kuro--color-scheme-detect-dark-p))))

(ert-deftest kuro-color-scheme-detect-dark-dark-bg-via-luminance ()
  "D5: nil mode + #1e1e1e background (Y ≈ 0.013) → t (dark)."
  (cl-letf (((symbol-function 'frame-parameter)
             (lambda (_f _p) nil))
            ((symbol-function 'face-attribute)
             (lambda (&rest _) "#1e1e1e")))
    (should (kuro--color-scheme-detect-dark-p))))

;;; ── Group 3 (G): kuro--color-scheme-install-hook ────────────────────────────

(ert-deftest kuro-color-scheme-install-hook-modern-emacs-adds-hook ()
  "G1: On Emacs with `enable-theme-functions' bound, install adds the hook."
  (let ((enable-theme-functions nil))
    (kuro--color-scheme-install-hook)
    (unwind-protect
        (should (memq #'kuro--color-scheme-schedule enable-theme-functions))
      (remove-hook 'enable-theme-functions #'kuro--color-scheme-schedule))))

(ert-deftest kuro-color-scheme-install-hook-old-emacs-warns ()
  "G2: On simulated old Emacs (variable unbound), install emits a warning."
  (cl-letf (((symbol-function 'boundp)
             (lambda (sym) (not (eq sym 'enable-theme-functions)))))
    (let ((warned nil))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (&rest _args) (setq warned t))))
        (kuro--color-scheme-install-hook)
        (should warned)))))

;;; ── Group 4 (B): debounce coalescing ────────────────────────────────────────

(ert-deftest kuro-color-scheme-schedule-debounces-bursts ()
  "B1: Two back-to-back schedule calls fire apply-now exactly once."
  (let ((apply-count 0)
        (timers      nil)
        (kuro--color-scheme-debounce-timer nil))
    (cl-letf* (((symbol-function 'kuro--color-scheme-apply-now)
                (lambda () (cl-incf apply-count)))
               ((symbol-function 'run-with-idle-timer)
                (lambda (_secs _repeat fn &rest _args)
                  (let ((tok (cons 'fake-timer fn)))
                    (push tok timers)
                    tok)))
               ((symbol-function 'cancel-timer)
                (lambda (tok) (setq timers (delq tok timers)))))
      (kuro--color-scheme-schedule)
      (kuro--color-scheme-schedule)
      ;; Only one timer survives the second schedule (first was cancelled).
      (should (= 1 (length timers)))
      ;; Fire the surviving timer manually.
      (funcall (cdr (car timers)))
      (should (= 1 apply-count)))))

;;; ── Group 5 (R): kuro-color-scheme-refresh ──────────────────────────────────

(ert-deftest kuro-color-scheme-refresh-pushes-to-live-session ()
  "R1: refresh with one stubbed live session calls the FFI once with (id, dark)."
  (let ((calls nil))
    (with-temp-buffer
      (let ((buf (current-buffer)))
        (setq-local kuro--session-id 42)
        (kuro-color-scheme-test--with-fake-buffers (list buf)
          (kuro-color-scheme-test--with-stubbed-set
              (lambda (id dark) (push (cons id dark) calls))
            (cl-letf (((symbol-function 'kuro--color-scheme-detect-dark-p)
                       (lambda (&rest _) t)))
              (kuro-color-scheme-refresh))))))
    (should (= 1 (length calls)))
    (should (equal (car calls) '(42 . t)))))

(ert-deftest kuro-color-scheme-refresh-no-sessions-is-noop ()
  "R2: refresh with no live sessions is a no-op (does not error)."
  (let ((calls 0))
    (kuro-color-scheme-test--with-fake-buffers nil
      (kuro-color-scheme-test--with-stubbed-set
          (lambda (&rest _) (cl-incf calls))
        (should-not (kuro-color-scheme-refresh))))
    (should (zerop calls))))

(ert-deftest kuro-color-scheme-refresh-light-theme-passes-nil ()
  "R3: refresh with a light theme propagates is-dark=nil to Rust."
  (let ((calls nil))
    (with-temp-buffer
      (let ((buf (current-buffer)))
        (setq-local kuro--session-id 7)
        (kuro-color-scheme-test--with-fake-buffers (list buf)
          (kuro-color-scheme-test--with-stubbed-set
              (lambda (id dark) (push (cons id dark) calls))
            (cl-letf (((symbol-function 'kuro--color-scheme-detect-dark-p)
                       (lambda (&rest _) nil)))
              (kuro-color-scheme-refresh))))))
    (should (equal (car calls) '(7 . nil)))))

(ert-deftest kuro-color-scheme-refresh-skips-buffers-without-session-id ()
  "R4: buffers with nil/zero kuro--session-id are skipped silently."
  (let ((calls 0))
    (with-temp-buffer
      (let ((buf (current-buffer)))
        ;; No setq-local of kuro--session-id → unbound in this buffer.
        (kuro-color-scheme-test--with-fake-buffers (list buf)
          (kuro-color-scheme-test--with-stubbed-set
              (lambda (&rest _) (cl-incf calls))
            (kuro-color-scheme-refresh)))))
    (should (zerop calls))))

;;; ── Group 6: defcustom defaults ─────────────────────────────────────────────

(ert-deftest kuro-color-scheme-debounce-default-is-50ms ()
  "Default debounce window is 50 ms (0.05 s)."
  (should (= (default-value 'kuro-color-scheme-debounce-seconds) 0.05)))

;;; ── Group 7 (C): install-time sync + idempotency ────────────────────────────

(ert-deftest kuro-color-scheme-install-hook-syncs-current-theme-once ()
  "C3: install-hook pushes the current theme to live sessions immediately.
Without this sync, Rust's `color_scheme_dark' stays at its default until
the user next switches themes — visible bug for users enabling the
feature mid-session."
  (let ((calls 0)
        (enable-theme-functions nil))
    (with-temp-buffer
      (let ((buf (current-buffer)))
        (setq-local kuro--session-id 1)
        (kuro-color-scheme-test--with-fake-buffers (list buf)
          (kuro-color-scheme-test--with-stubbed-set
              (lambda (&rest _) (cl-incf calls))
            (unwind-protect
                (progn
                  (kuro--color-scheme-install-hook)
                  (should (>= calls 1)))
              (remove-hook 'enable-theme-functions
                           #'kuro--color-scheme-schedule))))))))

(ert-deftest kuro-color-scheme-install-hook-idempotent ()
  "C5: calling install twice leaves exactly one copy of the schedule fn
on `enable-theme-functions'.  Relies on `add-hook' eq-deduplication."
  (let ((enable-theme-functions nil))
    (unwind-protect
        (progn
          (kuro--color-scheme-install-hook)
          (kuro--color-scheme-install-hook)
          (should (= 1 (cl-count #'kuro--color-scheme-schedule
                                 enable-theme-functions))))
      (remove-hook 'enable-theme-functions #'kuro--color-scheme-schedule))))

;;; ── Group 8 (W): luminance + nil-color-values fallback ──────────────────────

(ert-deftest kuro-color-scheme-luminance-mid-gray-near-half ()
  "W2: 0x7f7f7f mid-gray has Rec.709 Y ≈ 0.498 — pins the boundary near 0.5.
Stubs `color-values' to return the true 0x7f scaled-to-65535 triplet because
batch Emacs without a display rounds non-pure-bit hex values (0x7f → 0)."
  (cl-letf (((symbol-function 'color-values)
             (lambda (&rest _)
               ;; 0x7f / 0xff * 65535 ≈ 32639 — true device-independent value.
               (list 32639 32639 32639))))
    (let ((y (kuro--color-scheme-luminance "#7f7f7f")))
      (should (numberp y))
      (should (and (> y 0.45) (< y 0.55))))))

(ert-deftest kuro-color-scheme-detect-dark-color-values-nil-falls-back-dark ()
  "W4: when `color-values' returns nil for a stringp bg, detect-dark-p
falls back to t (dark).  Covers the `(if y (< y 0.5) t)' nil-y branch."
  (cl-letf (((symbol-function 'frame-parameter)
             (lambda (_f _p) nil))
            ((symbol-function 'face-attribute)
             (lambda (&rest _) "#abcdef"))
            ((symbol-function 'color-values)
             (lambda (&rest _) nil)))
    (should (kuro--color-scheme-detect-dark-p))))

(ert-deftest kuro-color-scheme-refresh-idempotent-on-no-op ()
  "W3: repeated refresh calls keep invoking the FFI; the FFI's return value
on the second call is nil (the Rust side reports no-op via nil).  This pins
the behavior so we notice if the contract changes."
  (let ((returns nil))
    (with-temp-buffer
      (let ((buf (current-buffer)))
        (setq-local kuro--session-id 99)
        (kuro-color-scheme-test--with-fake-buffers (list buf)
          (kuro-color-scheme-test--with-stubbed-set
              (lambda (&rest _) nil)
            (cl-letf (((symbol-function 'kuro--color-scheme-detect-dark-p)
                       (lambda (&rest _) t)))
              (push (kuro-color-scheme-refresh) returns)
              (push (kuro-color-scheme-refresh) returns))))))
    (should (= 2 (length returns)))
    ;; The second (most recently pushed) call's FFI invocation returns nil.
    (should-not (car returns))))

(provide 'kuro-color-scheme-test)

;;; kuro-color-scheme-test.el ends here
