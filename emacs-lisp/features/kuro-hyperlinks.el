;;; kuro-hyperlinks.el --- OSC 8 hyperlink overlay management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Renders clickable hyperlink overlays from OSC 8 escape sequences.
;; The Rust backend stamps hyperlink URIs on terminal cells;
;; this module polls those ranges and creates Emacs overlays with
;; mouse-clickable and keyboard-navigable behavior.

;;; Code:

(require 'kuro-ffi-osc)
(require 'kuro-keymap)
(require 'kuro-hyperlinks-macros)
(require 'kuro-url-safety)

(declare-function kuro--row-position "kuro-render-buffer" (row))

(defface kuro-hyperlink
  '((t :underline t :inherit link))
  "Face for OSC 8 hyperlinks in the Kuro terminal."
  :group 'kuro)

(defvar-local kuro--hyperlink-overlays nil
  "List of active hyperlink overlays in this buffer.")

(defconst kuro--hyperlink-keymap
  (kuro--define-keymap
    ([mouse-1] . kuro-open-hyperlink-at-point)
    ((kbd "RET") . kuro-open-hyperlink-at-point))
  "Keymap for hyperlink overlays.")

(defun kuro--hyperlink-range-entry-p (entry)
  "Return non-nil when ENTRY is a strictly typed hyperlink range."
  (pcase entry
    (`(,row ,start ,end ,uri)
     (and (integerp row)
          (<= 0 row)
          (integerp start)
          (<= 0 start)
          (integerp end)
          (< start end)
          (kuro--terminal-web-url-valid-p uri)))
    (_ nil)))

(defun kuro--hyperlink-buffer-range-p (beg end)
  "Return non-nil when BEG and END are valid overlay bounds."
  (and (integerp beg)
       (integerp end)
       (<= (point-min) beg)
       (< beg end)
       (<= end (point-max))))

(defun kuro-open-hyperlink-at-point ()
  "Open the OSC 8 hyperlink at point using `browse-url'."
  (interactive)
  (when-let* ((ov (car (overlays-at (point)))))
    (when-let* ((uri (overlay-get ov 'kuro-hyperlink-uri)))
      (if (kuro--terminal-web-url-valid-p uri)
          (browse-url uri)
        (message "kuro: blocked hyperlink target: %s"
                 (kuro--terminal-web-url-target-summary uri))))))

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
        (when (kuro--hyperlink-range-entry-p entry)
          (pcase-let ((`(,row ,start ,end ,uri) entry))
            (when-let* ((row-pos (kuro--row-position row)))
              (let* ((beg (+ row-pos start))
                     (e   (+ row-pos end)))
                (when (kuro--hyperlink-buffer-range-p beg e)
                  (kuro--make-hyperlink-overlay beg e uri))))))))))

(provide 'kuro-hyperlinks)

;;; kuro-hyperlinks.el ends here
