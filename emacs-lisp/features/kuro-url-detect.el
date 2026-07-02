;;; kuro-url-detect.el --- URL detection for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Idle-timer-based detection of clickable HTTP(S) URLs in the Kuro
;; terminal buffer.  URLs are highlighted and clickable via mouse or RET.

;;; Code:

(require 'cl-lib)
(require 'kuro-ffi)
(require 'kuro-keymap)
(require 'kuro-url-safety)

;;; Customization

(defcustom kuro-url-detection t
  "When non-nil, detect and highlight URLs in terminal output."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-url-detection-delay 0.5
  "Idle seconds before scanning visible region for URLs."
  :type 'float
  :group 'kuro)

;;; Internal state

(kuro--defvar-permanent-local kuro--url-overlays nil
  "List of active URL overlays in this buffer.")

(kuro--defvar-permanent-local kuro--url-detect-timer nil
  "Idle timer for URL detection in this buffer.")

;;; URL regex

(defconst kuro--url-regexp
  "https?://[^ \t\n\r\"'`>)}<|]*[^ \t\n\r\"'`>)}<|.,;:!?]"
  "Regexp matching HTTP(S) URLs in terminal output.
Greedily matches URL characters but excludes trailing punctuation.")

;;; Keymap (defined before functions that reference it)

(defvar kuro--url-keymap
  (kuro--define-keymap
    ([mouse-1] . kuro-open-url-at-point)
    ((kbd "RET") . kuro-open-url-at-point))
  "Keymap active on URL overlays.")

;;; Overlay management

(defun kuro--clear-url-overlays ()
  "Remove all URL detection overlays from the current buffer."
  (dolist (ov kuro--url-overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq kuro--url-overlays nil))

(defun kuro--url-detect-range-p (beg end)
  "Return non-nil when BEG and END are a strict in-buffer range."
  (and (integerp beg)
       (integerp end)
       (<= (point-min) beg)
       (< beg end)
       (<= end (point-max))))

(defun kuro--make-url-overlay (beg end url)
  "Create a clickable overlay from BEG to END for URL."
  (unless (kuro--url-detect-range-p beg end)
    (error "Invalid URL overlay range: %S..%S" beg end))
  (unless (kuro--terminal-web-url-valid-p url)
    (error "Invalid URL target: %S" url))
  (let ((ov (make-overlay beg end nil t nil)))
    (overlay-put ov 'kuro-url t)
    (overlay-put ov 'kuro-url-target url)
    (overlay-put ov 'face 'link)
    (overlay-put ov 'mouse-face 'highlight)
    (overlay-put ov 'help-echo url)
    (overlay-put ov 'keymap kuro--url-keymap)
    (push ov kuro--url-overlays)
    ov))

;;; Actions

(defun kuro-open-url-at-point ()
  "Open the URL overlay at point."
  (interactive)
  (let ((url (cl-some
              (lambda (ov)
                (let ((target (and (overlay-get ov 'kuro-url)
                                   (overlay-get ov 'kuro-url-target))))
                  (and (kuro--terminal-web-url-valid-p target) target)))
              (overlays-at (point)))))
    (when url
      (browse-url url))))

;;; Scanner

(defun kuro--overlay-with-marker-p (pos marker)
  "Return non-nil when an overlay at POS has MARKER set."
  (cl-some (lambda (ov) (overlay-get ov marker))
           (overlays-at pos)))

(defun kuro--scan-urls-in-region (beg end)
  "Scan region BEG to END for URLs, creating overlays."
  (save-excursion
    (when kuro-url-detection
      (goto-char beg)
      (while (re-search-forward kuro--url-regexp end t)
        (let ((url-beg (match-beginning 0))
              (url-end (match-end 0))
              (url (match-string-no-properties 0)))
          (unless (kuro--overlay-with-marker-p url-beg 'kuro-url)
            (when (kuro--terminal-web-url-valid-p url)
              (kuro--make-url-overlay url-beg url-end url))))))))

(defun kuro--url-detect-visible ()
  "Scan the visible portion of the buffer for URLs.
Called from the idle timer."
  (when (and (derived-mode-p 'kuro-mode)
             kuro-url-detection)
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
