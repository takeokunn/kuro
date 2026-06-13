;;; kuro-copy-mode-adv-test-2.el --- Copy-mode Groups 27-30: save-and-exit, toggle, occur, search  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-support)

;;; ── Group 27: kuro--copy-mode-save-and-exit ──────────────────────────────────

(ert-deftest kuro-copy-mode-test-save-and-exit-is-interactive ()
  "`kuro--copy-mode-save-and-exit' is an interactive command."
  (should (commandp #'kuro--copy-mode-save-and-exit)))

(ert-deftest kuro-copy-mode-test-save-and-exit-calls-kill-ring-save ()
  "`kuro--copy-mode-save-and-exit' calls `kill-ring-save' interactively."
  (let ((called nil))
    (cl-letf (((symbol-function 'kill-ring-save)
               (lambda (&rest _) (interactive) (setq called t)))
              ((symbol-function 'kuro--exit-copy-mode) #'ignore))
      (kuro--copy-mode-save-and-exit)
      (should called))))

(ert-deftest kuro-copy-mode-test-save-and-exit-exits-when-auto-exit-t ()
  "`kuro--copy-mode-save-and-exit' calls `kuro--exit-copy-mode' when auto-exit is t."
  (let ((exit-called nil)
        (kuro-copy-mode-auto-exit t))
    (cl-letf (((symbol-function 'kill-ring-save)
               (lambda (&rest _) (interactive) nil))
              ((symbol-function 'kuro--exit-copy-mode)
               (lambda () (setq exit-called t))))
      (kuro--copy-mode-save-and-exit)
      (should exit-called))))

(ert-deftest kuro-copy-mode-test-save-and-exit-stays-when-auto-exit-nil ()
  "`kuro--copy-mode-save-and-exit' does NOT call `kuro--exit-copy-mode' when auto-exit is nil."
  (let ((exit-called nil)
        (kuro-copy-mode-auto-exit nil))
    (cl-letf (((symbol-function 'kill-ring-save)
               (lambda (&rest _) (interactive) nil))
              ((symbol-function 'kuro--exit-copy-mode)
               (lambda () (setq exit-called t))))
      (kuro--copy-mode-save-and-exit)
      (should-not exit-called))))

;;; ── Group 28: kuro-copy-mode toggle ─────────────────────────────────────────

(ert-deftest kuro-copy-mode-test-toggle-errors-outside-kuro-mode ()
  "`kuro-copy-mode' signals user-error when not in a Kuro buffer."
  (with-temp-buffer
    (should-error (kuro-copy-mode) :type 'user-error)))

(ert-deftest kuro-copy-mode-test-toggle-enters-when-not-in-copy-mode ()
  "`kuro-copy-mode' calls `kuro--enter-copy-mode' when copy mode is inactive."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode nil)
    (let ((enter-called nil))
      (cl-letf (((symbol-function 'kuro--enter-copy-mode)
                 (lambda () (setq enter-called t))))
        (kuro-copy-mode)
        (should enter-called)))))

(ert-deftest kuro-copy-mode-test-toggle-exits-when-in-copy-mode ()
  "`kuro-copy-mode' calls `kuro--exit-copy-mode' when copy mode is already active."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode t)
    (let ((exit-called nil))
      (cl-letf (((symbol-function 'kuro--exit-copy-mode)
                 (lambda () (setq exit-called t))))
        (kuro-copy-mode)
        (should exit-called)))))

;;; ── Group 29: kuro-occur ─────────────────────────────────────────────────────

(ert-deftest kuro-copy-mode-test-occur-is-interactive ()
  "`kuro-occur' is an interactive command."
  (should (commandp #'kuro-occur)))

(ert-deftest kuro-copy-mode-test-occur-errors-outside-kuro-mode ()
  "`kuro-occur' signals user-error when not in a Kuro buffer."
  (with-temp-buffer
    (should-error (kuro-occur "pattern") :type 'user-error)))

(ert-deftest kuro-copy-mode-test-occur-enters-copy-mode-if-not-active ()
  "`kuro-occur' calls `kuro--enter-copy-mode' when not already in copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode nil)
    (let ((enter-called nil))
      (cl-letf (((symbol-function 'kuro--enter-copy-mode)
                 (lambda () (setq enter-called t)))
                ((symbol-function 'occur) #'ignore))
        (kuro-occur "test")
        (should enter-called)))))

(ert-deftest kuro-copy-mode-test-occur-skips-entry-when-already-active ()
  "`kuro-occur' does not call `kuro--enter-copy-mode' when already in copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode t)
    (let ((enter-called nil))
      (cl-letf (((symbol-function 'kuro--enter-copy-mode)
                 (lambda () (setq enter-called t)))
                ((symbol-function 'occur) #'ignore))
        (kuro-occur "test")
        (should-not enter-called)))))

(ert-deftest kuro-copy-mode-test-occur-passes-regexp-to-occur ()
  "`kuro-occur' calls `occur' with the provided regexp."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode t)
    (let ((received-regexp nil))
      (cl-letf (((symbol-function 'occur)
                 (lambda (re) (setq received-regexp re))))
        (kuro-occur "error-pattern")
        (should (string= received-regexp "error-pattern"))))))

;;; ── Group 30: kuro-search-forward / kuro-search-backward ─────────────────────

(ert-deftest kuro-copy-mode-test-search-forward-errors-outside-kuro ()
  "`kuro-search-forward' signals user-error when not in a Kuro buffer."
  (with-temp-buffer
    (should-error (kuro-search-forward) :type 'user-error)))

(ert-deftest kuro-copy-mode-test-search-forward-enters-copy-mode-if-needed ()
  "`kuro-search-forward' calls `kuro--enter-copy-mode' when not in copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode nil)
    (let ((enter-called nil))
      (cl-letf (((symbol-function 'kuro--enter-copy-mode)
                 (lambda () (setq enter-called t)))
                ((symbol-function 'isearch-forward) #'ignore))
        (kuro-search-forward)
        (should enter-called)))))

(ert-deftest kuro-copy-mode-test-search-forward-calls-isearch-forward ()
  "`kuro-search-forward' calls `isearch-forward' after ensuring copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode t)
    (let ((isearch-called nil))
      (cl-letf (((symbol-function 'isearch-forward)
                 (lambda () (setq isearch-called t))))
        (kuro-search-forward)
        (should isearch-called)))))

(ert-deftest kuro-copy-mode-test-search-backward-errors-outside-kuro ()
  "`kuro-search-backward' signals user-error when not in a Kuro buffer."
  (with-temp-buffer
    (should-error (kuro-search-backward) :type 'user-error)))

(ert-deftest kuro-copy-mode-test-search-backward-calls-isearch-backward ()
  "`kuro-search-backward' calls `isearch-backward' after ensuring copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (setq-local kuro--copy-mode t)
    (let ((isearch-called nil))
      (cl-letf (((symbol-function 'isearch-backward)
                 (lambda () (setq isearch-called t))))
        (kuro-search-backward)
        (should isearch-called)))))

(provide 'kuro-copy-mode-adv-test-2)
;;; kuro-copy-mode-adv-test-2.el ends here
