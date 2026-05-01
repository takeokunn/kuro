;;; kuro-url-detect.el --- URL and file:line detection for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Idle-timer-based detection of clickable URLs and file:line references
;; in the Kuro terminal buffer.  URLs are highlighted and clickable via
;; mouse or RET.  File:line patterns open the file at the specified line.

;;; Code:

(require 'cl-lib)
(require 'kuro-ffi)

;;; Customization

(defcustom kuro-url-detection t
  "When non-nil, detect and highlight URLs in terminal output."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-file-line-detection t
  "When non-nil, detect file:line patterns and make them clickable."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-url-detection-delay 0.5
  "Idle seconds before scanning visible region for URLs."
  :type 'float
  :group 'kuro)

;;; Internal state

(kuro--defvar-permanent-local kuro--url-overlays nil
  "List of active URL/file-reference overlays in this buffer.")

(kuro--defvar-permanent-local kuro--url-detect-timer nil
  "Idle timer for URL detection in this buffer.")

;;; URL regex

(defconst kuro--url-regexp
  "https?://[^] \t\n\r\"'`>)}<|]*[^] \t\n\r\"'`>)}<|.,;:!?]"
  "Regexp matching HTTP(S) URLs in terminal output.
Greedily matches URL characters but excludes trailing punctuation.")

;;; File:line regex (FR-005)

(defconst kuro--file-line-regexp
  "\\(/[^ \t\n\r:\"']+\\):\\([0-9]+\\)"
  "Regexp matching /path/to/file:LINE patterns.
Group 1 is the file path, group 2 is the line number.")

;;; Keymap (defined before functions that reference it)

(defvar kuro--url-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'kuro-open-url-at-point)
    (define-key map (kbd "RET") #'kuro-open-url-at-point)
    map)
  "Keymap active on URL overlays.")

;;; Overlay management

(defun kuro--clear-url-overlays ()
  "Remove all URL detection overlays from the current buffer."
  (dolist (ov kuro--url-overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq kuro--url-overlays nil))

(defun kuro--make-url-overlay (beg end url)
  "Create a clickable overlay from BEG to END for URL."
  (let ((ov (make-overlay beg end nil t nil)))
    (overlay-put ov 'kuro-url t)
    (overlay-put ov 'kuro-url-target url)
    (overlay-put ov 'face 'link)
    (overlay-put ov 'mouse-face 'highlight)
    (overlay-put ov 'help-echo url)
    (overlay-put ov 'keymap kuro--url-keymap)
    (push ov kuro--url-overlays)
    ov))

(defun kuro--make-file-line-overlay (beg end file line)
  "Create a clickable overlay from BEG to END for FILE at LINE."
  (let ((ov (make-overlay beg end nil t nil)))
    (overlay-put ov 'kuro-url t)
    (overlay-put ov 'kuro-file-target file)
    (overlay-put ov 'kuro-line-target line)
    (overlay-put ov 'face 'link)
    (overlay-put ov 'mouse-face 'highlight)
    (overlay-put ov 'help-echo (format "%s:%d" file line))
    (overlay-put ov 'keymap kuro--url-keymap)
    (push ov kuro--url-overlays)
    ov))

;;; Actions

(defun kuro-open-url-at-point ()
  "Open the URL or file reference at point."
  (interactive)
  (let ((ov (car (overlays-at (point)))))
    (when ov
      (cond
       ((overlay-get ov 'kuro-url-target)
        (browse-url (overlay-get ov 'kuro-url-target)))
       ((overlay-get ov 'kuro-file-target)
        (let ((file (overlay-get ov 'kuro-file-target))
              (line (overlay-get ov 'kuro-line-target)))
          (when (file-exists-p file)
            (find-file-other-window file)
            (when line
              (goto-char (point-min))
              (forward-line (1- line))))))))))

;;; Scanner

(defun kuro--scan-urls-in-region (beg end)
  "Scan region BEG to END for URLs and file:line patterns, creating overlays."
  (save-excursion
    (when kuro-url-detection
      (goto-char beg)
      (while (re-search-forward kuro--url-regexp end t)
        (let ((url-beg (match-beginning 0))
              (url-end (match-end 0))
              (url (match-string-no-properties 0)))
          (unless (cl-some (lambda (ov) (overlay-get ov 'kuro-url))
                           (overlays-at url-beg))
            (kuro--make-url-overlay url-beg url-end url)))))
    (when kuro-file-line-detection
      (goto-char beg)
      (while (re-search-forward kuro--file-line-regexp end t)
        (let ((file-beg (match-beginning 0))
              (file-end (match-end 0))
              (file (match-string-no-properties 1))
              (line (string-to-number (match-string-no-properties 2))))
          (unless (cl-some (lambda (ov) (overlay-get ov 'kuro-url))
                           (overlays-at file-beg))
            (when (file-exists-p file)
              (kuro--make-file-line-overlay file-beg file-end file line))))))))

(defun kuro--url-detect-visible ()
  "Scan the visible portion of the buffer for URLs and file references.
Called from the idle timer."
  (when (and (derived-mode-p 'kuro-mode)
             (or kuro-url-detection kuro-file-line-detection))
    (let ((win-start (window-start))
          (win-end (window-end nil t)))
      (dolist (ov kuro--url-overlays)
        (when (and (overlay-buffer ov)
                   (>= (overlay-start ov) win-start)
                   (<= (overlay-end ov) win-end))
          (delete-overlay ov)))
      (setq kuro--url-overlays
            (cl-remove-if-not #'overlay-buffer kuro--url-overlays))
      (kuro--scan-urls-in-region win-start win-end))))

;;; Timer management

(defun kuro--start-url-detection ()
  "Start the idle timer for URL detection."
  (unless kuro--url-detect-timer
    (setq kuro--url-detect-timer
          (run-with-idle-timer kuro-url-detection-delay t
                               #'kuro--url-detect-visible))))

(defun kuro--stop-url-detection ()
  "Stop the idle timer for URL detection."
  (when kuro--url-detect-timer
    (cancel-timer kuro--url-detect-timer)
    (setq kuro--url-detect-timer nil))
  (kuro--clear-url-overlays))

(provide 'kuro-url-detect)

;;; kuro-url-detect.el ends here
