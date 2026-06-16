;;; kuro-overlays-test-cases.el --- Overlay test case data  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-faces-attrs)

(defconst kuro-overlays-test--apply-blink-cases
  '((kuro-overlays-apply-blink-slow-creates-overlay
     :type slow
     :visible-var kuro--blink-visible-slow
     :initial-visible t
     :expected-invisible nil
     :doc "Slow blink overlay is created with visible phase.")
    (kuro-overlays-apply-blink-fast-creates-overlay
     :type fast
     :visible-var kuro--blink-visible-fast
     :initial-visible t
     :expected-invisible nil
     :doc "Fast blink overlay is created with visible phase.")
    (kuro-overlays-apply-blink-visible-when-visible
     :type slow
     :visible-var kuro--blink-visible-slow
     :initial-visible t
     :expected-invisible nil
     :doc "Slow blink overlay is visible when the slow phase is visible.")
    (kuro-overlays-apply-blink-invisible-when-hidden
     :type slow
     :visible-var kuro--blink-visible-slow
     :initial-visible nil
     :expected-invisible t
     :doc "Slow blink overlay is invisible when the slow phase is hidden."))
  "Data for `kuro--apply-blink-overlay' behavior tests.")

(defconst kuro-overlays-test--tick-blink-boundary-cases
  '((kuro-overlays-tick-blink-slow-toggles-at-interval
     :frame-fn kuro--blink-slow-frames
     :visible-var kuro--blink-visible-slow
     :other-visible-var nil
     :doc "Slow blink state toggles at the slow frame boundary.")
    (kuro-overlays-tick-blink-fast-toggles-at-interval
     :frame-fn kuro--blink-fast-frames
     :visible-var kuro--blink-visible-fast
     :other-visible-var nil
     :doc "Fast blink state toggles at the fast frame boundary.")
    (kuro-overlays-tick-blink-no-toggle-at-non-boundary
     :frame-fn nil
     :visible-var kuro--blink-visible-slow
     :other-visible-var kuro--blink-visible-fast
     :doc "Slow and fast blink states do not toggle away from a boundary."))
  "Data for `kuro--tick-blink-overlays' boundary behavior tests.")

(defconst kuro-overlays-test--apply-ffi-face-cases
  '((kuro-overlays-apply-ffi-face-at-blink-slow-creates-overlay
     :flags kuro--sgr-flag-blink-slow
     :assertion (:blink slow)
     :doc "FFI face range creates a slow blink overlay when slow blink is set.")
    (kuro-overlays-apply-ffi-face-at-blink-fast-creates-overlay
     :flags kuro--sgr-flag-blink-fast
     :assertion (:blink fast)
     :doc "FFI face range creates a fast blink overlay when fast blink is set.")
    (kuro-overlays-apply-ffi-face-at-hidden-sets-invisible
     :flags kuro--sgr-flag-hidden
     :assertion (:text-property invisible)
     :doc "FFI face range sets invisible text property when hidden is set.")
    (kuro-overlays-apply-ffi-face-at-no-blink-no-overlay
     :flags 0
     :assertion (:no-blink-overlay)
     :doc "Default FFI face range does not create blink overlays."))
  "Data for `kuro--apply-ffi-face-at' side-effect tests.")

(defconst kuro-overlays-test--toggle-blink-phase-cases
  '((kuro-overlays-toggle-blink-phase-slow-flips-state
     :type slow
     :visible-var kuro--blink-visible-slow
     :double-toggle t
     :doc "Slow blink phase toggles and can be toggled back.")
    (kuro-overlays-toggle-blink-phase-fast-flips-state
     :type fast
     :visible-var kuro--blink-visible-fast
     :double-toggle nil
     :doc "Fast blink phase toggles."))
  "Data for simple `kuro--toggle-blink-phase' state tests.")

(provide 'kuro-overlays-test-cases)
;;; kuro-overlays-test-cases.el ends here
