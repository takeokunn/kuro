;;; kuro-overlays-test-macros.el --- Overlay test macros  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-overlays)
(require 'kuro-navigation)
(require 'kuro-overlays-test-cases)

;;; Helpers

(defmacro kuro-overlays-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with overlay state initialized to defaults.
Sets the following buffer-local variables:
  `kuro--blink-overlays' nil (no active blink overlays)
  `kuro--blink-visible-slow' t (slow blink phase starts visible)
  `kuro--blink-visible-fast' t (fast blink phase starts visible)
  `kuro--image-overlays' nil (no active image overlays)
  `kuro--prompt-positions' nil (no known prompt positions)
  `kuro--blink-frame-count' 0 (frame counter reset)
  `inhibit-read-only' t (allows buffer modification in tests)"
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--blink-overlays nil)
           (kuro--image-overlays nil)
           (kuro--prompt-positions nil)
           (kuro--blink-frame-count 0)
           (kuro--blink-visible-slow t)
           (kuro--blink-visible-fast t))
       ,@body)))

;;; Test generators

(defmacro kuro-overlays-test--def-apply-blink-case (name &rest plist)
  "Define NAME from a PLIST entry in `kuro-overlays-test--apply-blink-cases'."
  (declare (indent 1))
  (let ((type (plist-get plist :type))
        (visible-var (plist-get plist :visible-var))
        (initial-visible (plist-get plist :initial-visible))
        (expected-invisible (plist-get plist :expected-invisible))
        (doc (plist-get plist :doc)))
    `(ert-deftest ,name ()
       ,doc
       (kuro-overlays-test--with-buffer
         (insert "Hello\n")
         (setq ,visible-var ,initial-visible)
         (kuro--apply-blink-overlay 1 6 ',type)
         (should (= (length kuro--blink-overlays) 1))
         (let ((ov (car kuro--blink-overlays)))
           (should (overlay-get ov 'kuro-blink))
           (should (eq (overlay-get ov 'kuro-blink-type) ',type))
           ,(if expected-invisible
                `(should (overlay-get ov 'invisible))
              `(should-not (overlay-get ov 'invisible))))))))

(defmacro kuro-overlays-test--deftest-apply-blink-cases ()
  "Define `kuro--apply-blink-overlay' tests from case data."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-overlays-test--def-apply-blink-case ,@case))
               kuro-overlays-test--apply-blink-cases)))

(defmacro kuro-overlays-test--def-tick-blink-boundary-case (name &rest plist)
  "Define NAME from a PLIST entry in `kuro-overlays-test--tick-blink-boundary-cases'."
  (declare (indent 1))
  (let ((frame-fn (plist-get plist :frame-fn))
        (visible-var (plist-get plist :visible-var))
        (other-visible-var (plist-get plist :other-visible-var))
        (doc (plist-get plist :doc)))
    `(ert-deftest ,name ()
       ,doc
       (kuro-overlays-test--with-buffer
         ,(if frame-fn
              `(let ((boundary (,frame-fn)))
                 (setq kuro--blink-frame-count (1- boundary)
                       ,visible-var t)
                 (kuro--tick-blink-overlays)
                 (should (= kuro--blink-frame-count boundary))
                 (should-not ,visible-var))
            `(progn
               (setq kuro--blink-frame-count 5
                     ,visible-var t
                     ,other-visible-var t)
               (kuro--tick-blink-overlays)
               (should ,visible-var)
               (should ,other-visible-var)))))))

(defmacro kuro-overlays-test--deftest-tick-blink-boundary-cases ()
  "Define `kuro--tick-blink-overlays' boundary tests from case data."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-overlays-test--def-tick-blink-boundary-case ,@case))
               kuro-overlays-test--tick-blink-boundary-cases)))

(defmacro kuro-overlays-test--def-apply-ffi-face-case (name &rest plist)
  "Define NAME from a PLIST entry in `kuro-overlays-test--apply-ffi-face-cases'."
  (declare (indent 1))
  (let ((flags (plist-get plist :flags))
        (assertion (plist-get plist :assertion))
        (doc (plist-get plist :doc)))
    `(ert-deftest ,name ()
       ,doc
       (kuro-overlays-test--with-buffer
         (insert "Hello\n")
         (kuro--apply-ffi-face-at 1 6 #xFF000000 #xFF000000 ,flags 0)
         ,(pcase assertion
            (`(:blink ,type)
             `(progn
                (should (> (length kuro--blink-overlays) 0))
                (should (eq (overlay-get (car kuro--blink-overlays) 'kuro-blink-type)
                            ',type))))
            (`(:text-property ,property)
             `(should (get-text-property 1 ',property)))
            (`(:no-blink-overlay)
             `(should (null kuro--blink-overlays))))))))

(defmacro kuro-overlays-test--deftest-apply-ffi-face-cases ()
  "Define `kuro--apply-ffi-face-at' tests from case data."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-overlays-test--def-apply-ffi-face-case ,@case))
               kuro-overlays-test--apply-ffi-face-cases)))

(defmacro kuro-overlays-test--def-toggle-blink-phase-case (name &rest plist)
  "Define NAME from a PLIST entry in `kuro-overlays-test--toggle-blink-phase-cases'."
  (declare (indent 1))
  (let ((type (plist-get plist :type))
        (visible-var (plist-get plist :visible-var))
        (double-toggle (plist-get plist :double-toggle))
        (doc (plist-get plist :doc)))
    `(ert-deftest ,name ()
       ,doc
       (kuro-overlays-test--with-buffer
         (setq ,visible-var t)
         (kuro--toggle-blink-phase ',type)
         (should-not ,visible-var)
         ,@(when double-toggle
             `((kuro--toggle-blink-phase ',type)
               (should ,visible-var)))))))

(defmacro kuro-overlays-test--deftest-toggle-blink-phase-cases ()
  "Define simple `kuro--toggle-blink-phase' state tests from case data."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-overlays-test--def-toggle-blink-phase-case ,@case))
               kuro-overlays-test--toggle-blink-phase-cases)))

(provide 'kuro-overlays-test-macros)
;;; kuro-overlays-test-macros.el ends here
