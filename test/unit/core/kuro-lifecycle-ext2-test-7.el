;;; kuro-lifecycle-ext2-test-7.el --- Lifecycle tests — Group 38: shell-integration-dir paths  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-lifecycle-test-support)


;;; ── Group 38: kuro--shell-integration-dir — all branches ──────────────────
;;
;; The function has four observable paths:
;;   A. `kuro-shell-integration' is nil               → nil (already tested in Group 33)
;;   B. flag non-nil, `locate-library' returns nil    → nil
;;   C. flag non-nil, library found, dir missing       → nil
;;   D. flag non-nil, library found, dir exists        → dir string
;;
;; Group 38 covers paths B, C, and D.

(ert-deftest kuro-lifecycle--shell-integration-dir-nil-when-locate-fails ()
  "`kuro--shell-integration-dir' returns nil when `locate-library' cannot find kuro files."
  (let ((kuro-shell-integration t))
    (cl-letf (((symbol-function 'locate-library) (lambda (_name) nil))
              ((symbol-function 'file-directory-p) (lambda (_path) nil)))
      (should (null (kuro--shell-integration-dir))))))

(ert-deftest kuro-lifecycle--shell-integration-dir-nil-when-dir-missing ()
  "`kuro--shell-integration-dir' returns nil when the shell/ directory does not exist."
  (let ((kuro-shell-integration t))
    (cl-letf (((symbol-function 'locate-library)
               (lambda (_name) "/fake/path/kuro-lifecycle.el"))
              ((symbol-function 'file-directory-p) (lambda (_path) nil)))
      (should (null (kuro--shell-integration-dir))))))

(ert-deftest kuro-lifecycle--shell-integration-dir-returns-dir-when-found ()
  "`kuro--shell-integration-dir' returns the shell/ path when it exists."
  (let ((kuro-shell-integration t)
        (fake-lib "/home/user/.emacs.d/lisp/kuro/emacs-lisp/core/kuro-lifecycle.el"))
    (cl-letf (((symbol-function 'locate-library)
               (lambda (_name) fake-lib))
              ((symbol-function 'file-directory-p) (lambda (_path) t)))
      (let ((result (kuro--shell-integration-dir)))
        (should (stringp result))
        (should (string-suffix-p "/shell" result))))))

(ert-deftest kuro-lifecycle--shell-integration-dir-path-construction ()
  "`kuro--shell-integration-dir' builds the path as <parent-of-parent>/shell."
  (let ((kuro-shell-integration t)
        (fake-lib "/proj/emacs-lisp/core/kuro-lifecycle.el")
        captured-path)
    (cl-letf (((symbol-function 'locate-library)
               (lambda (_name) fake-lib))
              ((symbol-function 'file-directory-p)
               (lambda (path) (setq captured-path path) t)))
      (kuro--shell-integration-dir)
      ;; /proj/emacs-lisp/core/ → parent dir → /proj/emacs-lisp/ → parent dir → /proj/
      ;; → expand "shell" relative = /proj/shell
      (should (string-suffix-p "/shell" captured-path)))))


;;; ── Group 39: kuro--clear-session-state macro — structural ──────────────────

(ert-deftest kuro-lifecycle--clear-session-state-macroexpands-to-setq ()
  "`kuro--clear-session-state' single-step expands to a `setq' form."
  (let ((exp (macroexpand-1 '(kuro--clear-session-state))))
    (should (eq (car exp) 'setq))))

(ert-deftest kuro-lifecycle--run-session-setup-fns-macroexpands-to-progn ()
  "`kuro--run-session-setup-fns' expands to the fixed setup sequence."
  (should (equal (macroexpand-1 '(kuro--run-session-setup-fns))
                 '(progn
                    (kuro--setup-char-width-table)
                    (kuro--setup-fontset)
                    (kuro--ensure-left-margin)
                    (kuro--setup-dnd)
                    (kuro--setup-compilation)
                    (kuro--setup-bookmark)
                    (kuro--color-scheme-install-hook)))))


(provide 'kuro-lifecycle-ext2-test-7)
;;; kuro-lifecycle-ext2-test-7.el ends here
