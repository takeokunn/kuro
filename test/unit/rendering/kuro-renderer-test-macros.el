;;; kuro-renderer-test-macros.el --- Shared renderer test macros  -*- lexical-binding: t; -*-

;;; Commentary:

;; Test-generating macros used by renderer test split files.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces)
(require 'kuro-renderer)
(require 'kuro-render-buffer)
(require 'kuro-binary-decoder)
(require 'kuro-overlays)
(require 'kuro-ffi)
(require 'kuro-renderer-test-cases)

(defvar-local kuro--last-rows 0)
(defvar-local kuro--last-cols 0)

(defmacro kuro-renderer-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer suitable for renderer tests."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           kuro--cursor-marker
           (kuro--scroll-offset 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(defmacro kuro-renderer-helpers-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with renderer helper state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized t)
           (kuro--scroll-offset 0)
           (kuro--last-rows 24)
           (kuro--last-cols 80)
           (kuro--tui-mode-frame-count 0)
           (kuro--tui-mode-active nil)
           (kuro--last-dirty-count 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro-streaming-latency-mode t)
           kuro--stream-idle-timer
           kuro--cursor-marker
           kuro--blink-overlays
           kuro--image-overlays
           kuro--timer)
       ,@body)))

(defmacro kuro-renderer-test--def-apply-title-update-case (case)
  "Define one `kuro--apply-title-update' test from CASE."
  (pcase-let ((`(,name ,doc ,title ,checks) case))
    (cl-labels
        ((check-form
          (check)
          (pcase-let ((`(,kind . ,args) check))
            (pcase kind
              ('buffer-name
               (pcase-let ((`(,regexp) args))
                 `(should (string-match-p ,regexp (buffer-name)))))
              ('buffer-name-unchanged
               '(should (equal (buffer-name) name-before)))
              ('frame-name
               (pcase-let ((`(,expected) args))
                 `(should (equal frame-name-set ,expected))))
              (_ (error "Unknown apply-title-update check: %S" check))))))
      `(ert-deftest ,name ()
         ,doc
         (kuro-renderer-helpers-test--with-buffer
           (let ((frame-name-set nil)
                 (name-before (buffer-name)))
             (cl-letf (((symbol-function 'kuro--get-and-clear-title)
                        (lambda () ,title))
                       ((symbol-function 'get-buffer-window)
                        (lambda (_buf _all) (selected-window)))
                       ((symbol-function 'set-frame-parameter)
                        (lambda (_frame param val)
                          (when (eq param 'name)
                            (setq frame-name-set val)))))
               (kuro--apply-title-update)
               ,@(mapcar #'check-form checks))))))))

(defmacro kuro-renderer-test--deftest-apply-title-update-cases ()
  "Define shared `kuro--apply-title-update' tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-renderer-test--def-apply-title-update-case ,case))
               kuro-renderer-test--apply-title-update-cases)))

(defmacro kuro-renderer-test--def-update-tui-streaming-timer-case (case)
  "Define one `kuro--update-tui-streaming-timer' test from CASE."
  (pcase-let ((`(,name ,doc ,bindings ,checks) case))
    (cl-labels
        ((check-form
          (check)
          (pcase-let ((`(,kind . ,args) check))
            (pcase kind
              ('frame-count
               (pcase-let ((`(,expected) args))
                 `(should (= kuro--tui-mode-frame-count ,expected))))
              ('tui-active
               (pcase-let ((`(,expected) args))
                 (if expected
                     '(should kuro--tui-mode-active)
                   '(should-not kuro--tui-mode-active))))
              ('stop-called
               (pcase-let ((`(,expected) args))
                 (if expected
                     '(should stop-called)
                   '(should-not stop-called))))
              ('start-called
               (pcase-let ((`(,expected) args))
                 (if expected
                     '(should start-called)
                   '(should-not start-called))))
              ('switch-rate
               (pcase-let ((`(,expected) args))
                 (if expected
                     `(should (= switch-rate ,expected))
                   '(should-not switch-rate))))
              (_ (error "Unknown update-tui-streaming-timer check: %S" check))))))
      `(ert-deftest ,name ()
         ,doc
         (kuro-renderer-helpers-test--with-buffer
           (setq ,@(cl-mapcan (lambda (binding)
                                (pcase-let ((`(,var ,value) binding))
                                  (list var value)))
                              bindings))
           (let ((stop-called nil)
                 (start-called nil)
                 (switch-rate nil))
             (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer)
                        (lambda () (setq stop-called t)))
                       ((symbol-function 'kuro--start-stream-idle-timer)
                        (lambda () (setq start-called t)))
                       ((symbol-function 'kuro--switch-render-timer)
                        (lambda (rate) (setq switch-rate rate))))
               (should-not (condition-case err
                               (progn (kuro--update-tui-streaming-timer) nil)
                             (error err))))
             ,@(mapcar #'check-form checks)))))))

(defmacro kuro-renderer-test--deftest-update-tui-streaming-timer-cases ()
  "Define shared `kuro--update-tui-streaming-timer' tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-renderer-test--def-update-tui-streaming-timer-case ,case))
               kuro-renderer-test--update-tui-streaming-timer-cases)))

(defmacro kuro-renderer-test--def-sanitize-title-base-case (case)
  "Define one `kuro--sanitize-title' base test from CASE."
  (pcase-let ((`(,name ,doc ,assertions) case))
    `(ert-deftest ,name ()
       ,doc
       ,@(mapcar (lambda (assertion)
                   (pcase-let ((`(,input ,expected) assertion))
                     `(should (equal (kuro--sanitize-title ,input) ,expected))))
                 assertions))))

(defmacro kuro-renderer-test--deftest-sanitize-title-base-cases ()
  "Define shared `kuro--sanitize-title' base tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-renderer-test--def-sanitize-title-base-case ,case))
               kuro-renderer-test--sanitize-title-base-cases)))

(defmacro kuro-renderer-test--def-update-line-full-case (case)
  "Define one `kuro--update-line-full' base test from CASE."
  (pcase-let ((`(,name ,doc ,initial ,row ,text ,checks) case))
    (cl-labels
        ((check-form
          (check)
          (pcase-let ((`(,kind . ,args) check))
            (pcase kind
              ('line-matches
               (pcase-let ((`(,line ,regexp) args))
                 `(progn
                    (goto-char (point-min))
                    (forward-line ,line)
                    (should (looking-at ,regexp)))))
              ('line-count
               (pcase-let ((`(,expected) args))
                 `(should (= (count-lines (point-min) (point-max)) ,expected))))
              (_ (error "Unknown update-line-full check: %S" check))))))
      `(ert-deftest ,name ()
         ,doc
         (kuro-renderer-test--with-buffer
           (insert ,initial)
           (kuro--update-line-full ,row ,text nil nil)
           ,@(mapcar #'check-form checks))))))

(defmacro kuro-renderer-test--deftest-update-line-full-cases ()
  "Define shared `kuro--update-line-full' base tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-renderer-test--def-update-line-full-case ,case))
               kuro-renderer-test--update-line-full-cases)))

(defmacro kuro-renderer-test--def-reset-cursor-cache-case (case)
  "Define one `kuro--reset-cursor-cache' runtime test from CASE."
  (pcase-let ((`(,name ,doc ,bindings ,reset-count) case))
    `(ert-deftest ,name ()
       ,doc
       (with-temp-buffer
         (let ,bindings
           ,@(make-list reset-count '(kuro--reset-cursor-cache))
           (should (null kuro--last-cursor-row))
           (should (null kuro--last-cursor-col))
           (should (null kuro--last-cursor-visible))
           (should (null kuro--last-cursor-shape)))))))

(defmacro kuro-renderer-test--deftest-reset-cursor-cache-cases ()
  "Define shared `kuro--reset-cursor-cache' runtime tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-renderer-test--def-reset-cursor-cache-case ,case))
               kuro-renderer-test--reset-cursor-cache-cases)))

(defmacro kuro-renderer-test--def-sanitize-title-edge-case (case)
  "Define one `kuro--sanitize-title' edge test from CASE."
  (pcase-let ((`(,name ,doc ,assertions) case))
    `(ert-deftest ,name ()
       ,doc
       ,@(mapcar (lambda (assertion)
                   (pcase-let ((`(,input ,expected) assertion))
                     `(should (equal (kuro--sanitize-title ,input) ,expected))))
                 assertions))))

(defmacro kuro-renderer-test--deftest-sanitize-title-edge-cases ()
  "Define shared `kuro--sanitize-title' edge tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-renderer-test--def-sanitize-title-edge-case ,case))
               kuro-renderer-test--sanitize-title-edge-cases)))

(provide 'kuro-renderer-test-macros)
;;; kuro-renderer-test-macros.el ends here
