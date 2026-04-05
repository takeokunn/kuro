;;; kuro-bookmark.el --- Bookmark support for Kuro terminal buffers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Integrates Kuro with Emacs' bookmark system.
;; Bookmarking a Kuro buffer saves the shell command and working directory.
;; Jumping to the bookmark creates a new terminal session in that directory.

;;; Code:

(require 'bookmark)

(declare-function kuro-create "kuro-lifecycle" (&optional command buffer-name))

(defvar kuro-shell)

(defun kuro-bookmark-make-record ()
  "Create a bookmark record for the current Kuro terminal buffer.
Saves the shell command and current working directory."
  `(,(format "kuro: %s" (or default-directory "~"))
    (handler . kuro-bookmark-jump)
    (shell . ,(or (bound-and-true-p kuro--shell-command) kuro-shell))
    (directory . ,(or default-directory "~"))
    (buffer-name . ,(buffer-name))))

;;;###autoload
(defun kuro-bookmark-jump (bookmark)
  "Jump to a Kuro terminal BOOKMARK.
Creates a new terminal session with the saved shell command
in the saved working directory."
  (let ((shell (bookmark-prop-get bookmark 'shell))
        (dir (bookmark-prop-get bookmark 'directory))
        (buf-name (bookmark-prop-get bookmark 'buffer-name)))
    (let ((default-directory (or dir "~")))
      (kuro-create shell (or buf-name (generate-new-buffer-name "*kuro*"))))))

(defun kuro--setup-bookmark ()
  "Configure bookmark support for the current Kuro buffer."
  (setq-local bookmark-make-record-function #'kuro-bookmark-make-record))

(provide 'kuro-bookmark)
;;; kuro-bookmark.el ends here
