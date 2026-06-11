;;; kuro-render-buffer-test-support.el --- Shared helpers for render-buffer tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared test helpers for kuro-render-buffer.el unit tests.
;; All three test files require this support file before defining tests:
;;   kuro-render-buffer-test.el      — Groups 1-9, 21-26
;;   kuro-render-buffer-ext-test.el  — Groups 15-20, 27-28
;;   kuro-render-buffer-ext2-test.el — Groups 8-14, 29

;;; Code:

(require 'cl-lib)
(require 'kuro-render-buffer)

;;; Primary test buffer helper

(defmacro kuro-render-buffer-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with render-buffer state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized nil)
           (kuro--scroll-offset 0)
           (kuro--last-rows 24)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro--blink-overlays-by-row nil)
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

;;; Utility

(defun kuro-render-buffer-test--line-count (buf)
  "Return the number of lines in BUF."
  (with-current-buffer buf
    (count-lines (point-min) (point-max))))

;;; Face-call recording and stubbing

(defmacro kuro-render-buffer-test--capture-face-calls (calls-var &rest body)
  "Run BODY while recording `kuro--apply-ffi-face-at' calls in CALLS-VAR."
  (declare (indent 1))
  `(let ((,calls-var nil))
     (cl-letf (((symbol-function 'kuro--apply-ffi-face-at)
                (lambda (s e fg bg fl _ul)
                  (push (list s e fg bg fl) ,calls-var))))
       ,@body)))

(defmacro kuro-render-buffer-test--with-render-stubs (&rest body)
  "Run BODY with face and image overlay side-effects stubbed to no-ops.
Stubs `kuro--apply-ffi-face-at' and `kuro--clear-row-image-overlays' so
tests focused on text content or position cache logic are not affected by
face application or image overlay management side-effects."
  `(cl-letf (((symbol-function 'kuro--apply-ffi-face-at)        #'ignore)
             ((symbol-function 'kuro--clear-row-image-overlays)  #'ignore))
     ,@body))


;;; Cursor test buffer helper

(defmacro kuro-render-buffer-cursor-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with cursor-update state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--scroll-offset 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           kuro--cursor-marker
           kuro--last-cursor-row
           kuro--last-cursor-col
           kuro--last-cursor-visible
           kuro--last-cursor-shape
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(provide 'kuro-render-buffer-test-support)

;;; kuro-render-buffer-test-support.el ends here
