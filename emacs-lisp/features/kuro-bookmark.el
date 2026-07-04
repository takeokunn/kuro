;;; kuro-bookmark.el --- Bookmark support for Kuro terminal buffers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:
;; Integrates Kuro with Emacs' bookmark system.
;; Bookmarking a Kuro buffer saves its working directory and display buffer
;; name.  Executable commands are deliberately not persisted.

;;; Code:

(require 'bookmark)

(declare-function kuro-create "kuro-lifecycle" (&optional command buffer-name))

(defun kuro-bookmark--string-has-control-character-p (value)
  "Return non-nil when VALUE has an ASCII control character."
  (string-match-p "[[:cntrl:]]" value))

(defun kuro-bookmark--safe-directory (directory)
  "Return DIRECTORY as a local directory name, or nil if it is unsafe."
  (when (and (stringp directory)
             (< 0 (length directory))
             (not (kuro-bookmark--string-has-control-character-p directory))
             (not (file-remote-p directory))
             (file-directory-p directory))
    (file-name-as-directory directory)))

(defun kuro-bookmark--safe-buffer-name (name)
  "Return NAME when it is safe to reuse as a buffer name."
  (when (and (stringp name)
             (< 0 (length name))
             (not (kuro-bookmark--string-has-control-character-p name)))
    name))

(defun kuro-bookmark-make-record ()
  "Create a bookmark record for the current Kuro terminal buffer.
Saves the current working directory and buffer name.  The shell command is not
persisted because bookmark files are user-editable executable boundaries."
  (let ((directory (or (kuro-bookmark--safe-directory default-directory)
                       (expand-file-name "~/")))
        (buffer-name (or (kuro-bookmark--safe-buffer-name (buffer-name))
                         (generate-new-buffer-name "*kuro*"))))
    `(,(format "kuro: %s" directory)
      (handler . kuro-bookmark-jump)
      (directory . ,directory)
      (buffer-name . ,buffer-name))))

;;;###autoload
(defun kuro-bookmark-jump (bookmark)
  "Jump to a Kuro terminal BOOKMARK.
Creates a new terminal session with the configured default command in the saved
working directory."
  (let ((dir (or (kuro-bookmark--safe-directory
                  (bookmark-prop-get bookmark 'directory))
                 (expand-file-name "~/")))
        (buf-name (kuro-bookmark--safe-buffer-name
                   (bookmark-prop-get bookmark 'buffer-name))))
    (let ((default-directory dir))
      (kuro-create nil (or buf-name (generate-new-buffer-name "*kuro*"))))))

(defun kuro--setup-bookmark ()
  "Configure bookmark support for the current Kuro buffer."
  (setq-local bookmark-make-record-function #'kuro-bookmark-make-record))

(provide 'kuro-bookmark)
;;; kuro-bookmark.el ends here
