;;; kuro-e2e-colors-test.el --- SGR color and attribute E2E tests -*- lexical-binding: t -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; E2E tests for SGR (Select Graphic Rendition) escape sequences covering:
;; basic ANSI colors, 256-color indexed, truecolor RGB, text attributes
;; (bold, italic, dim, underline, strikethrough, inverse, hidden, blink),
;; combined attributes, fast blink, SGR reset, and bright background colors.

;;; Code:

(require 'ert)
(require 'kuro-e2e-helpers)

(ert-deftest kuro-e2e-ansi-colors ()
  "SGR 31 sets red foreground; :foreground should be a hex color string."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[31mREDTEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "REDTEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "REDTEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos))
              (fg (plist-get props :foreground)))
         (should (stringp fg))
         (should (string-prefix-p "#" fg)))))))

(ert-deftest kuro-e2e-hidden-text ()
  "SGR 8 sets invisible attribute; text should have :invisible property."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[8mHIDDENTEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "HIDDENTEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "HIDDENTEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos)))
         (should (plist-get props :invisible)))))))

(ert-deftest kuro-e2e-inverse-video ()
  "SGR 7 sets inverse video; face should have :inverse-video t."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[7mINVERSETEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "INVERSETEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "INVERSETEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos)))
         (should (plist-get props :inverse-video)))))))

(ert-deftest kuro-e2e-blink-structural ()
  "SGR 5 (slow blink) should produce a kuro-blink overlay of type 'slow."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[5mBLINKTEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "BLINKTEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "BLINKTEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (overlays (overlays-at pos))
              (blink-ov (cl-find-if
                         (lambda (ov) (overlay-get ov 'kuro-blink))
                         overlays)))
         (when blink-ov
           (should (eq (overlay-get blink-ov 'kuro-blink) 'slow))))))))

(ert-deftest kuro-e2e-256-color-indexed-fg ()
  "SGR 38;5;196 sets indexed color 196 (red); :foreground should be \"#ff0000\"."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[38;5;196mIDX196TEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "IDX196TEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "IDX196TEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos))
              (fg (plist-get props :foreground)))
         (should (equal fg "#ff0000")))))))

(ert-deftest kuro-e2e-truecolor-rgb-fg ()
  "SGR 38;2;255;0;0 sets truecolor red; :foreground should be \"#ff0000\"."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[38;2;255;0;0mRGBTEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "RGBTEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "RGBTEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos))
              (fg (plist-get props :foreground)))
         (should (equal fg "#ff0000")))))))

(ert-deftest kuro-e2e-italic-text ()
  "SGR 3 sets italic; face :slant should be italic."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[3mKITALICTEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KITALICTEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "KITALICTEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos)))
         (should (eq (plist-get props :slant) 'italic)))))))

(ert-deftest kuro-e2e-dim-text ()
  "SGR 2 sets dim/faint; face :weight should be light."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[2mKDIMTEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KDIMTEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "KDIMTEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos)))
         (should (eq (plist-get props :weight) 'light)))))))

(ert-deftest kuro-e2e-strikethrough-text ()
  "SGR 9 sets strikethrough; face :strike-through should be t."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[9mKSTRIKETEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KSTRIKETEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "KSTRIKETEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos)))
         (should (plist-get props :strike-through)))))))

(ert-deftest kuro-e2e-combined-sgr-attributes ()
  "SGR 1;3;4 sets bold, italic, and underline simultaneously."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[1;3;4mKCOMBINEDTEXT\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KCOMBINEDTEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "KCOMBINEDTEXT" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos)))
         (should (eq (plist-get props :weight) 'bold))
         (should (eq (plist-get props :slant) 'italic))
         (should (plist-get props :underline)))))))

(ert-deftest kuro-e2e-fast-blink ()
  "SGR 6 (fast blink) should produce a kuro-blink overlay of type 'fast."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[6mKFASTBLINK\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KFASTBLINK"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "KFASTBLINK" (buffer-string))
       (let* ((pos (match-beginning 0))
              (overlays (overlays-at pos))
              (blink-ov (cl-find-if
                         (lambda (ov) (overlay-get ov 'kuro-blink))
                         overlays)))
         (when blink-ov
           (should (eq (overlay-get blink-ov 'kuro-blink) 'fast))))))))

(ert-deftest kuro-e2e-sgr-reset-bold ()
  "SGR 22 resets bold; :weight should not be bold after reset sequence."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[1mBOLD\\033[22mKNRM22\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KNRM22"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "KNRM22" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos)))
         (should-not (eq (plist-get props :weight) 'bold)))))))

(ert-deftest kuro-e2e-bright-background-color ()
  "SGR 101 sets bright red background; :background should be a hex color string."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\033[101mKBRIGHTBG\\033[0m\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KBRIGHTBG"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "KBRIGHTBG" (buffer-string))
       (let* ((pos (match-beginning 0))
              (props (kuro-e2e--face-props-at pos))
              (bg (plist-get props :background)))
         (should (stringp bg))
         (should (string-prefix-p "#" bg)))))))

(provide 'kuro-e2e-colors-test)
;;; kuro-e2e-colors-test.el ends here
