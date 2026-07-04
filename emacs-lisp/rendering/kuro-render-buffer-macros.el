;;; kuro-render-buffer-macros.el --- Macro helpers for Kuro render buffer  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers extracted from `kuro-render-buffer.el'.

;;; Code:

(defmacro kuro--with-buffer-edit (&rest body)
  "Execute BODY with read-only and modification hooks suppressed.
Saves and restores point via `save-excursion'."
  `(let ((inhibit-read-only t)
         (inhibit-modification-hooks t))
     (save-excursion
       ,@body)))

(defmacro kuro--with-current-render-row (row &rest body)
  "Bind `kuro--current-render-row' to ROW while executing BODY.
Restores the previous render row even if BODY signals, so callers do not need
to manage the sentinel manually."
  `(let ((kuro--current-render-row ,row))
     (unwind-protect
         (progn ,@body)
       (setq kuro--current-render-row -1))))

(defmacro kuro--with-rewritten-line (row text col-to-buf &rest body)
  "Rewrite ROW with TEXT, then execute BODY with updated line bounds.
Stores COL-TO-BUF before the rewrite, refreshes the row-position cache after
the insert, and binds `line-start' and `new-line-end' for BODY so callers can
focus on the post-rewrite work.  BODY runs inside `kuro--with-buffer-edit'."
  (declare (indent 4))
  `(progn
     (kuro--store-col-to-buf ,row ,col-to-buf)
     (kuro--with-buffer-edit
       (kuro--ensure-buffer-row-exists ,row)
       (let* ((line-start (point))
              (old-end (line-end-position))
              (old-len (- old-end line-start)))
         (kuro--clear-row-overlays ,row old-end)
         (delete-region line-start old-end)
         (insert ,text)
         ;; Capture the replacement extent once so post-rewrite helpers share it.
         ;; `line-end-position' is recomputed after insert to account for
         ;; multibyte text.
         (let ((new-line-end (line-end-position)))
           (kuro--update-row-position-cache-after-line-change
            ,row old-len (- new-line-end line-start) new-line-end)
           ,@body)))))

(provide 'kuro-render-buffer-macros)

;;; kuro-render-buffer-macros.el ends here
