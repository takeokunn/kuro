;;; kuro-mux-test-10.el --- ERT tests for kuro-mux.el — Groups 9-11  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

(defmacro kuro-mux-test--with-registry (&rest body)
  "Run BODY with a clean `kuro-mux--sessions' registry, restored on exit."
  `(let ((kuro-mux--sessions nil)
         (kuro-mux-tab-bar-mode nil))
     ,@body
     (dolist (buf kuro-mux--sessions)
       (when (buffer-live-p buf)
         (kill-buffer buf)))
     (setq kuro-mux--sessions nil)))

(defmacro kuro-mux-test--make-session (name)
  "Create a mock kuro-mode buffer named NAME and register it.
Returns the buffer."
  `(let ((buf (get-buffer-create ,name)))
     (with-current-buffer buf
       (kuro-mode)
       (kuro-mux--register))
     buf))

;;; Group 9 — Hook management

(ert-deftest kuro-mux-test-install-hooks-adds-kuro-mode-hook ()
  "`kuro-mux--install-hooks' adds `kuro-mux--on-session-created' to `kuro-mode-hook'."
  (let ((kuro-mode-hook nil))
    (kuro-mux--install-hooks)
    (should (memq #'kuro-mux--on-session-created kuro-mode-hook))
    ;; cleanup
    (setq kuro-mode-hook nil)))

(ert-deftest kuro-mux-test-install-hooks-adds-kill-buffer-hook ()
  "`kuro-mux--install-hooks' adds `kuro-mux--on-session-killed' to `kill-buffer-hook'."
  (let ((kill-buffer-hook nil))
    (kuro-mux--install-hooks)
    (should (memq #'kuro-mux--on-session-killed kill-buffer-hook))
    (setq kill-buffer-hook nil)))

(ert-deftest kuro-mux-test-uninstall-hooks-removes-hooks ()
  "`kuro-mux--uninstall-hooks' removes both hooks."
  (let ((kuro-mode-hook   (list #'kuro-mux--on-session-created))
        (kill-buffer-hook (list #'kuro-mux--on-session-killed)))
    (kuro-mux--uninstall-hooks)
    (should-not (memq #'kuro-mux--on-session-created kuro-mode-hook))
    (should-not (memq #'kuro-mux--on-session-killed  kill-buffer-hook))))


;;; Group 10 — Directory recorded at registration

(ert-deftest kuro-mux-test-register-records-directory ()
  "`kuro-mux--register' stores `default-directory' in `kuro-mux--directory'."
  (kuro-mux-test--with-registry
   (let ((buf (get-buffer-create "*mux-dir1*")))
     (with-current-buffer buf
       (kuro-mode)
       (setq default-directory "/tmp/")
       (kuro-mux--register))
     (should (string= (with-current-buffer buf kuro-mux--directory) "/tmp/"))
     (kill-buffer buf))))


;;; Group 11 — Prefix keymap (tmux-style)

(ert-deftest kuro-mux-test-prefix-map-is-keymap ()
  "`kuro-mux-prefix-map' is a keymap."
  (should (keymapp kuro-mux-prefix-map)))

(defconst kuro-mux-test--prefix-map-bindings
  '((kuro-mux-test-prefix-map-binds-next           "n"   kuro-mux-next)
    (kuro-mux-test-prefix-map-binds-prev           "p"   kuro-mux-prev)
    (kuro-mux-test-prefix-map-binds-switch         "s"   kuro-mux-switch-by-name)
    (kuro-mux-test-prefix-map-binds-split-right    "%"   kuro-mux-split-right)
    (kuro-mux-test-prefix-map-binds-split-below    "\""  kuro-mux-split-below)
    (kuro-mux-test-prefix-map-binds-create         "c"   kuro-mux-create)
    (kuro-mux-test-prefix-map-binds-rename         ","   kuro-mux-rename)
    (kuro-mux-test-prefix-map-binds-save-layout    "S"   kuro-mux-save-layout)
    (kuro-mux-test-prefix-map-binds-restore-layout "R"   kuro-mux-restore-layout)
    (kuro-mux-test-prefix-map-binds-copy-mode      "["   kuro-copy-mode)
    (kuro-mux-test-prefix-map-binds-search-forward "/"   kuro-search-forward)
    (kuro-mux-test-prefix-map-binds-rename-dollar  "$"   kuro-mux-rename)
    (kuro-mux-test-prefix-map-binds-help           "?"   kuro-mux-help)
    (kuro-mux-test-prefix-map-binds-detach         "d"   kuro-mux-detach)
    (kuro-mux-test-prefix-map-binds-zoom           "z"   kuro-mux-zoom)
    (kuro-mux-test-prefix-map-binds-kill           "&"   kuro-mux-kill))
  "Table of (test-name key fn) for `kuro-mux-prefix-map' binding assertions.")

(defmacro kuro-mux-test--def-prefix-binding (test-name key fn)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux-prefix-map' binds %S to `%s'." key fn)
     (should (eq (lookup-key kuro-mux-prefix-map (kbd ,key)) #',fn))))

(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-next           "n"   kuro-mux-next)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-prev           "p"   kuro-mux-prev)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-switch         "s"   kuro-mux-switch-by-name)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-split-right    "%"   kuro-mux-split-right)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-split-below    "\""  kuro-mux-split-below)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-create         "c"   kuro-mux-create)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-rename         ","   kuro-mux-rename)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-save-layout    "S"   kuro-mux-save-layout)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-restore-layout "R"   kuro-mux-restore-layout)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-copy-mode      "["   kuro-copy-mode)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-search-forward "/"   kuro-search-forward)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-rename-dollar  "$"   kuro-mux-rename)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-help           "?"   kuro-mux-help)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-detach         "d"   kuro-mux-detach)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-zoom           "z"   kuro-mux-zoom)
(kuro-mux-test--def-prefix-binding kuro-mux-test-prefix-map-binds-kill           "&"   kuro-mux-kill)

(ert-deftest kuro-mux-test-help-is-interactive ()
  "`kuro-mux-help' is an interactive command."
  (should (commandp #'kuro-mux-help)))

(ert-deftest kuro-mux-test--all-prefix-map-bindings-present ()
  "Every entry in `kuro-mux-test--prefix-map-bindings' is bound in `kuro-mux-prefix-map'."
  (dolist (entry kuro-mux-test--prefix-map-bindings)
    (let ((key (cadr entry))
          (fn  (caddr entry)))
      (should (eq (lookup-key kuro-mux-prefix-map (kbd key)) fn)))))

(provide 'kuro-mux-test-10)
;;; kuro-mux-test-10.el ends here
