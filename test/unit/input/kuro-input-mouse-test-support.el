;;; kuro-input-mouse-test-support.el --- Shared helpers for mouse input tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared test support for kuro-input-mouse unit tests.
;; This file centralizes the event stubs and helper macros used by the split
;; mouse test files.

;;; Code:

(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))
(unless (fboundp 'kuro--mouse-mode-query)
  (defalias 'kuro--mouse-mode-query (lambda () 0)))
(unless (fboundp 'kuro--scroll-up)
  (defalias 'kuro--scroll-up (lambda (_n) nil)))
(unless (fboundp 'kuro--scroll-down)
  (defalias 'kuro--scroll-down (lambda (_n) nil)))
(unless (fboundp 'kuro--get-scroll-offset)
  (defalias 'kuro--get-scroll-offset (lambda () 0)))
(unless (fboundp 'kuro--render-cycle)
  (defalias 'kuro--render-cycle (lambda () nil)))
(unless (fboundp 'kuro--update-scroll-indicator)
  (defalias 'kuro--update-scroll-indicator (lambda () nil)))

(require 'kuro-input-mouse)

(defmacro kuro-input-mouse-test--with-send (mode sgr pixel col row &rest body)
  "Execute BODY with mouse stubs installed and `sent' bound."
  (declare (indent 5))
  `(with-temp-buffer
     (setq-local kuro--mouse-mode ,mode
                 kuro--mouse-sgr ,sgr
                 kuro--mouse-pixel-mode ,pixel)
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'event-start)
                  (lambda (_ev) 'fake-pos))
                 ((symbol-function 'posn-col-row)
                  (lambda (_pos) (cons ,col ,row)))
                 ((symbol-function 'posn-x-y)
                  (lambda (_pos) (cons ,col ,row))))
         ,@body))))

(defmacro kuro-input-mouse-test--with-send-and-type (mode sgr pixel col row event-type &rest body)
  "Like `kuro-input-mouse-test--with-send' but stubs `event-basic-type'."
  (declare (indent 6))
  `(with-temp-buffer
     (setq-local kuro--mouse-mode ,mode
                 kuro--mouse-sgr ,sgr
                 kuro--mouse-pixel-mode ,pixel)
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'event-basic-type)
                  (lambda (_ev) ,event-type))
                 ((symbol-function 'event-start)
                  (lambda (_ev) 'fake-pos))
                 ((symbol-function 'posn-col-row)
                  (lambda (_pos) (cons ,col ,row)))
                 ((symbol-function 'posn-x-y)
                  (lambda (_pos) (cons ,col ,row))))
         ,@body))))

(defmacro kuro-mouse-test--with-event (col row &rest body)
  "Execute BODY with event position functions stubbed for COL and ROW."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'event-start)
               (lambda (_ev) 'fake-pos))
              ((symbol-function 'posn-col-row)
               (lambda (_pos) (cons ,col ,row)))
              ((symbol-function 'posn-x-y)
               (lambda (_pos) (cons ,col ,row))))
     ,@body))

(provide 'kuro-input-mouse-test-support)

;;; kuro-input-mouse-test-support.el ends here
