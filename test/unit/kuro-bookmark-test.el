;;; kuro-bookmark-test.el --- Unit tests for kuro-bookmark.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-bookmark.el — bookmark integration for Kuro terminals.
;;
;; Groups:
;;   Group 1: kuro-bookmark-make-record (alist structure, keys, defaults)
;;   Group 2: kuro-bookmark-jump (delegates to kuro-create)
;;   Group 3: kuro--setup-bookmark (sets bookmark-make-record-function)

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'bookmark)

;; Bootstrap load-path and stubs
(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

;; Ensure FFI stubs exist before loading kuro-bookmark (which requires bookmark,
;; and kuro-lifecycle transitively requires kuro-ffi).
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
               kuro-core-set-scrollback-max-lines
               kuro-core-detach
               kuro-core-attach
               kuro-core-list-sessions))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(require 'kuro-config)
(require 'kuro-bookmark)

;;; ── Group 1: kuro-bookmark-make-record ─────────────────────────────────────────

(ert-deftest kuro-bookmark--make-record-returns-alist ()
  "kuro-bookmark-make-record returns a non-nil list."
  (with-temp-buffer
    (let ((record (kuro-bookmark-make-record)))
      (should (listp record))
      (should (stringp (car record))))))

(ert-deftest kuro-bookmark--make-record-has-handler ()
  "Bookmark record includes a handler entry pointing to kuro-bookmark-jump."
  (with-temp-buffer
    (let ((record (kuro-bookmark-make-record)))
      (should (eq (alist-get 'handler (cdr record)) 'kuro-bookmark-jump)))))

(ert-deftest kuro-bookmark--make-record-has-shell ()
  "Bookmark record includes the shell key."
  (with-temp-buffer
    (let ((record (kuro-bookmark-make-record)))
      (should (assq 'shell (cdr record))))))

(ert-deftest kuro-bookmark--make-record-has-directory ()
  "Bookmark record includes the directory key."
  (with-temp-buffer
    (let ((record (kuro-bookmark-make-record)))
      (should (assq 'directory (cdr record))))))

(ert-deftest kuro-bookmark--make-record-has-buffer-name ()
  "Bookmark record includes the buffer-name key."
  (with-temp-buffer
    (let ((record (kuro-bookmark-make-record)))
      (should (assq 'buffer-name (cdr record))))))

(ert-deftest kuro-bookmark--make-record-uses-shell-command-when-set ()
  "When kuro--shell-command is set, the record uses it for the shell key."
  (with-temp-buffer
    (setq-local kuro--shell-command "/bin/zsh")
    (let ((record (kuro-bookmark-make-record)))
      (should (equal (alist-get 'shell (cdr record)) "/bin/zsh")))))

(ert-deftest kuro-bookmark--make-record-falls-back-to-kuro-shell ()
  "When kuro--shell-command is nil, the record uses kuro-shell."
  (with-temp-buffer
    (setq-local kuro--shell-command nil)
    (let ((kuro-shell "/bin/fish"))
      (let ((record (kuro-bookmark-make-record)))
        (should (equal (alist-get 'shell (cdr record)) "/bin/fish"))))))

(ert-deftest kuro-bookmark--make-record-directory-defaults-to-home ()
  "When default-directory is nil, directory defaults to \"~\"."
  (with-temp-buffer
    (let ((default-directory nil))
      (let ((record (kuro-bookmark-make-record)))
        (should (equal (alist-get 'directory (cdr record)) "~"))))))

(ert-deftest kuro-bookmark--make-record-uses-default-directory ()
  "Bookmark record uses default-directory when set."
  (with-temp-buffer
    (let ((default-directory "/tmp/"))
      (let ((record (kuro-bookmark-make-record)))
        (should (equal (alist-get 'directory (cdr record)) "/tmp/"))))))

(ert-deftest kuro-bookmark--make-record-name-includes-directory ()
  "Bookmark name contains the directory."
  (with-temp-buffer
    (let ((default-directory "/tmp/"))
      (let ((record (kuro-bookmark-make-record)))
        (should (string-match-p "/tmp/" (car record)))
        (should (string-prefix-p "kuro: " (car record)))))))

;;; ── Group 2: kuro-bookmark-jump ────────────────────────────────────────────────

(ert-deftest kuro-bookmark--jump-calls-kuro-create ()
  "kuro-bookmark-jump calls kuro-create with the saved shell and buffer-name."
  (let ((create-args nil))
    (cl-letf (((symbol-function 'kuro-create)
               (lambda (cmd buf) (setq create-args (list cmd buf)))))
      (let ((bookmark '("kuro: /tmp/"
                         (handler . kuro-bookmark-jump)
                         (shell . "/bin/bash")
                         (directory . "/tmp/")
                         (buffer-name . "*kuro-test*"))))
        (kuro-bookmark-jump bookmark)
        (should (equal (car create-args) "/bin/bash"))
        (should (equal (cadr create-args) "*kuro-test*"))))))

(ert-deftest kuro-bookmark--jump-sets-default-directory ()
  "kuro-bookmark-jump binds default-directory to the saved directory."
  (let ((captured-dir nil))
    (cl-letf (((symbol-function 'kuro-create)
               (lambda (_cmd _buf) (setq captured-dir default-directory))))
      (let ((bookmark '("kuro: /home/user/"
                         (handler . kuro-bookmark-jump)
                         (shell . "/bin/sh")
                         (directory . "/home/user/")
                         (buffer-name . "*kuro*"))))
        (kuro-bookmark-jump bookmark)
        (should (equal captured-dir "/home/user/"))))))

(ert-deftest kuro-bookmark--jump-nil-directory-defaults-to-home ()
  "kuro-bookmark-jump uses \"~\" when the saved directory is nil."
  (let ((captured-dir nil))
    (cl-letf (((symbol-function 'kuro-create)
               (lambda (_cmd _buf) (setq captured-dir default-directory))))
      (let ((bookmark '("kuro: ~"
                         (handler . kuro-bookmark-jump)
                         (shell . "/bin/sh")
                         (directory . nil)
                         (buffer-name . "*kuro*"))))
        (kuro-bookmark-jump bookmark)
        (should (equal captured-dir "~"))))))

(ert-deftest kuro-bookmark--jump-nil-buffer-name-generates-new ()
  "kuro-bookmark-jump generates a new buffer name when saved name is nil."
  (let ((create-buf nil))
    (cl-letf (((symbol-function 'kuro-create)
               (lambda (_cmd buf) (setq create-buf buf))))
      (let ((bookmark '("kuro: /tmp/"
                         (handler . kuro-bookmark-jump)
                         (shell . "/bin/sh")
                         (directory . "/tmp/")
                         (buffer-name . nil))))
        (kuro-bookmark-jump bookmark)
        (should (stringp create-buf))
        (should (string-match-p "\\*kuro\\*" create-buf))))))

;;; ── Group 3: kuro--setup-bookmark ──────────────────────────────────────────────

(ert-deftest kuro-bookmark--setup-sets-record-function ()
  "kuro--setup-bookmark sets bookmark-make-record-function buffer-locally."
  (with-temp-buffer
    (kuro--setup-bookmark)
    (should (eq bookmark-make-record-function #'kuro-bookmark-make-record))))

(ert-deftest kuro-bookmark--setup-is-buffer-local ()
  "kuro--setup-bookmark only affects the current buffer."
  (let ((original bookmark-make-record-function))
    (with-temp-buffer
      (kuro--setup-bookmark)
      (should (eq bookmark-make-record-function #'kuro-bookmark-make-record)))
    (should (eq bookmark-make-record-function original))))

(provide 'kuro-bookmark-test)

;;; kuro-bookmark-test.el ends here
