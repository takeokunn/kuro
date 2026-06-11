;;; kuro-mux-test-6.el --- Unit tests for kuro-mux.el — Groups 12-14  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)



;;; Group 12 — kuro-mux-install-keys

(ert-deftest kuro-mux-test-install-keys-binds-prefix ()
  "`kuro-mux-install-keys' binds the prefix map under `kuro-mux-prefix-key'."
  (let ((map (make-sparse-keymap))
        (kuro-mux-prefix-key "C-c m"))
    (kuro-mux-install-keys map)
    (should (eq (lookup-key map (kbd "C-c m")) kuro-mux-prefix-map))))

(ert-deftest kuro-mux-test-install-keys-respects-custom-prefix ()
  "`kuro-mux-install-keys' honors a custom `kuro-mux-prefix-key'."
  (let ((map (make-sparse-keymap))
        (kuro-mux-prefix-key "C-c j"))
    (kuro-mux-install-keys map)
    (should (eq (lookup-key map (kbd "C-c j")) kuro-mux-prefix-map))))

(ert-deftest kuro-mux-test-install-keys-returns-keymap ()
  "`kuro-mux-install-keys' returns the modified keymap."
  (let ((map (make-sparse-keymap)))
    (should (eq (kuro-mux-install-keys map) map))))

(ert-deftest kuro-mux-test-install-keys-errors-without-keymap ()
  "`kuro-mux-install-keys' errors when given a non-keymap argument."
  ;; Passing a non-keymap value forces the (keymapp map) guard to fail.
  (should-error (kuro-mux-install-keys 'not-a-keymap) :type 'user-error))

(ert-deftest kuro-mux-test-install-keys-reaches-command-via-prefix ()
  "A full prefix+key lookup resolves to the bound mux command."
  (let ((map (make-sparse-keymap))
        (kuro-mux-prefix-key "C-c m"))
    (kuro-mux-install-keys map)
    (should (eq (lookup-key map (kbd "C-c m n")) #'kuro-mux-next))))


;;; Group 13 — kuro-mux-create

(ert-deftest kuro-mux-test-create-calls-kuro-create ()
  "`kuro-mux-create' delegates to `kuro-create'."
  (let ((called-with :unset))
    (cl-letf (((symbol-function 'kuro-create)
               (lambda (&optional cmd &rest _) (setq called-with cmd))))
      (let ((kuro-shell "bash"))
        (kuro-mux-create))
      (should (equal called-with "bash")))))

(ert-deftest kuro-mux-test-create-uses-explicit-command ()
  "`kuro-mux-create' passes an explicit COMMAND through to `kuro-create'."
  (let ((called-with :unset))
    (cl-letf (((symbol-function 'kuro-create)
               (lambda (&optional cmd &rest _) (setq called-with cmd))))
      (kuro-mux-create "zsh")
      (should (equal called-with "zsh")))))


;;; Group 14 — kuro-mux-setup prefix installation

(ert-deftest kuro-mux-test-setup-installs-keys-when-enabled ()
  "`kuro-mux-setup' installs prefix keys when `kuro-mux-install-prefix-keys' is t."
  (let ((kuro-mux-install-prefix-keys t)
        (installed nil))
    (cl-letf (((symbol-function 'kuro-mux--install-hooks) #'ignore)
              ((symbol-function 'kuro-mux-install-keys)
               (lambda (&rest _) (setq installed t))))
      ;; Provide a kuro-mode-map so the guard passes
      (let ((kuro-mode-map (make-sparse-keymap)))
        (kuro-mux-setup))
      (should installed))))

(ert-deftest kuro-mux-test-setup-skips-keys-when-disabled ()
  "`kuro-mux-setup' does not install prefix keys when disabled."
  (let ((kuro-mux-install-prefix-keys nil)
        (installed nil))
    (cl-letf (((symbol-function 'kuro-mux--install-hooks) #'ignore)
              ((symbol-function 'kuro-mux-install-keys)
               (lambda (&rest _) (setq installed t))))
      (let ((kuro-mode-map (make-sparse-keymap)))
        (kuro-mux-setup))
      (should-not installed))))

(provide 'kuro-mux-test-6)
;;; kuro-mux-test-6.el ends here
