;;; kuro-hyperlinks.el --- OSC 8 hyperlink overlay management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Renders clickable hyperlink overlays from OSC 8 escape sequences.
;; The Rust backend stamps hyperlink URIs on terminal cells;
;; this module polls those ranges and creates Emacs overlays with
;; mouse-clickable and keyboard-navigable behavior.

;;; Code:

(require 'kuro-ffi-osc)

(declare-function kuro--row-position "kuro-render-buffer" (row))

(defface kuro-hyperlink
  '((t :underline t :inherit link))
  "Face for OSC 8 hyperlinks in the Kuro terminal."
  :group 'kuro)

(defvar-local kuro--hyperlink-overlays nil
  "List of active hyperlink overlays in this buffer.")

(defvar kuro--hyperlink-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'kuro-open-hyperlink-at-point)
    (define-key map (kbd "RET") #'kuro-open-hyperlink-at-point)
    map)
  "Keymap for hyperlink overlays.")

(defconst kuro--hyperlink-allowed-schemes '("https" "http" "ftp" "ftps" "mailto")
  "URI schemes permitted for OSC 8 hyperlink navigation.
Blocks potentially dangerous schemes like file:, data:, javascript:,
and OS-registered protocol handlers.")

(defun kuro--uri-scheme-allowed-p (uri)
  "Return non-nil if URI has a permitted scheme."
  (when-let ((scheme (and (string-match "\\`\\([a-zA-Z][a-zA-Z0-9+.-]*\\):" uri)
                          (downcase (match-string 1 uri)))))
    (member scheme kuro--hyperlink-allowed-schemes)))

(defun kuro-open-hyperlink-at-point ()
  "Open the OSC 8 hyperlink at point using `browse-url'."
  (interactive)
  (when-let ((ov (car (overlays-at (point)))))
    (when-let ((uri (overlay-get ov 'kuro-hyperlink-uri)))
      (if (kuro--uri-scheme-allowed-p uri)
          (browse-url uri)
        (message "kuro: blocked hyperlink with disallowed scheme: %s"
                 (truncate-string-to-width uri 80))))))

(defun kuro--clear-hyperlink-overlays ()
  "Remove all hyperlink overlays from the current buffer."
  (mapc #'delete-overlay kuro--hyperlink-overlays)
  (setq kuro--hyperlink-overlays nil))

(defun kuro--apply-hyperlink-ranges ()
  "Poll hyperlink ranges from Rust and create overlays.
Each range is (ROW START END URI).  START and END are character
offsets within the row text.  Overlays are created with the
`kuro-hyperlink' face and a clickable keymap."
  (let ((ranges (kuro--poll-hyperlink-ranges)))
    (when (or ranges kuro--hyperlink-overlays)
      (kuro--clear-hyperlink-overlays)
      (dolist (entry ranges)
        (pcase-let ((`(,row ,start ,end ,uri) entry))
          (when-let ((row-pos (kuro--row-position row)))
            (let* ((beg (+ row-pos start))
                   (e   (+ row-pos end))
                   (ov  (make-overlay beg e nil t nil)))
              (overlay-put ov 'face 'kuro-hyperlink)
              (overlay-put ov 'kuro-hyperlink-uri uri)
              (overlay-put ov 'mouse-face 'highlight)
              (overlay-put ov 'help-echo uri)
              (overlay-put ov 'keymap kuro--hyperlink-keymap)
              (push ov kuro--hyperlink-overlays))))))))

(provide 'kuro-hyperlinks)

;;; kuro-hyperlinks.el ends here
