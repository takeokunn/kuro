;;; kuro-compilation-test.el --- Unit tests for kuro-compilation.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-compilation.el — compilation error navigation.
;;
;; Groups:
;;   Group 1: kuro--setup-compilation   (enable/skip based on defcustom)
;;   Group 2: kuro--teardown-compilation (disable/safe when inactive)
;;   Group 3: kuro-compilation-navigation      (defcustom exists, default value)

;;; Code:

(require 'ert)
(require 'kuro-compilation)

;;; ── Group 1: kuro--setup-compilation ───────────────────────────────────────────

(ert-deftest kuro-compilation--setup-enables-when-mode-t ()
  "kuro--setup-compilation enables compilation-shell-minor-mode when
kuro-compilation-navigation is t."
  (with-temp-buffer
    (let ((kuro-compilation-navigation t))
      (kuro--setup-compilation)
      (should (bound-and-true-p compilation-shell-minor-mode))
      ;; Clean up
      (compilation-shell-minor-mode -1))))

(ert-deftest kuro-compilation--setup-noop-when-mode-nil ()
  "kuro--setup-compilation does nothing when kuro-compilation-navigation is nil."
  (with-temp-buffer
    (let ((kuro-compilation-navigation nil))
      (kuro--setup-compilation)
      (should-not (bound-and-true-p compilation-shell-minor-mode)))))

;;; ── Group 2: kuro--teardown-compilation ────────────────────────────────────────

(ert-deftest kuro-compilation--teardown-disables-mode ()
  "kuro--teardown-compilation disables compilation-shell-minor-mode."
  (with-temp-buffer
    (compilation-shell-minor-mode 1)
    (should (bound-and-true-p compilation-shell-minor-mode))
    (kuro--teardown-compilation)
    (should-not (bound-and-true-p compilation-shell-minor-mode))))

(ert-deftest kuro-compilation--teardown-safe-when-not-active ()
  "kuro--teardown-compilation does not error when mode is not active."
  (with-temp-buffer
    (should-not (bound-and-true-p compilation-shell-minor-mode))
    (kuro--teardown-compilation)
    (should-not (bound-and-true-p compilation-shell-minor-mode))))

;;; ── Group 3: kuro-compilation-navigation defcustom ───────────────────────────────────

(ert-deftest kuro-compilation--defcustom-exists-and-defaults-to-t ()
  "kuro-compilation-navigation defcustom exists and defaults to t."
  (should (boundp 'kuro-compilation-navigation))
  (should (eq kuro-compilation-navigation t)))

(provide 'kuro-compilation-test)
;;; kuro-compilation-test.el ends here
