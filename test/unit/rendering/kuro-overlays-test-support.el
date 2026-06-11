;;; kuro-overlays-test-support.el --- Shared helpers  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-overlays)
(require 'kuro-faces-attrs)


(require 'ert)
(require 'cl-lib)
(require 'kuro-overlays)
(require 'kuro-faces-attrs)

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


(provide 'kuro-overlays-test-support)
;;; kuro-overlays-test-support.el ends here
