;;; kuro-faces-attrs-test-2.el --- Tests for kuro-faces-attrs.el — Groups 11-13  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces-attrs)

(defmacro kuro-faces-attrs-test--ul-with-color (test-name style color style-sym desc)
  "Define a with-color ert-deftest for kuro--underline-style-to-face-prop."
  `(ert-deftest ,test-name ()
     ,desc
     (let ((result (kuro--underline-style-to-face-prop ,style ,color)))
       (should (equal (plist-get result :color) ,color))
       (should (eq (plist-get result :style) ',style-sym)))))

;;; Group 11: kuro--underline-style-to-face-prop — style-0 ignores color arg

(ert-deftest kuro-faces-attrs--underline-style0-with-color-still-nil ()
  "Style 0 returns nil even when underline-color is non-nil."
  (should-not (kuro--underline-style-to-face-prop 0 "#ff0000"))
  (should-not (kuro--underline-style-to-face-prop 0 "#ffffff")))

(ert-deftest kuro-faces-attrs--underline-style-unknown-with-color-is-t ()
  "Unknown style value with color still returns t (plain fallback; color ignored)."
  (should (eq t (kuro--underline-style-to-face-prop 42 "#aabbcc")))
  (should (eq t (kuro--underline-style-to-face-prop 6 "#123456"))))

(kuro-faces-attrs-test--ul-with-color kuro-faces-attrs--underline-style-dashed-color-preserves-style 5 "#001122" dashes "Style 5 with color has :style dashes (not line or wave).")
(kuro-faces-attrs-test--ul-with-color kuro-faces-attrs--underline-style-dotted-color-preserves-style 4 "#334455" dots   "Style 4 with color has :style dots (not line).")

;;; Group 12: kuro--attrs-to-face-props — bold+dim cond priority and named colors

(ert-deftest kuro-faces-attrs--attrs-to-face-props-bold-takes-priority-over-dim ()
  "When both bold (0x01) and dim (0x02) flags are set, bold wins (:weight bold)."
  ;; The cond in kuro--attrs-to-face-props: (cond (bold ...) (dim ...)) — bold tested first.
  (let ((props (kuro--attrs-to-face-props :default :default #x03 nil)))
    (should (eq (plist-get props :weight) 'bold))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-named-fg-resolves ()
  "Named foreground color is resolved to a hex string via kuro--named-colors."
  ;; 'red' should be in kuro--named-colors as a hex string.
  (let ((props (kuro--attrs-to-face-props '(named . "red") :default 0 nil)))
    (let ((fg (plist-get props :foreground)))
      (should (stringp fg))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" fg)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-named-bg-resolves ()
  "Named background color is resolved to a hex string via kuro--named-colors."
  (let ((props (kuro--attrs-to-face-props :default '(named . "blue") 0 nil)))
    (let ((bg (plist-get props :background)))
      (should (stringp bg))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" bg)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-indexed-fg-resolves ()
  "Indexed foreground color (cube range) resolves to a hex string."
  (let ((props (kuro--attrs-to-face-props '(indexed . 196) :default 0 nil)))
    (let ((fg (plist-get props :foreground)))
      (should (stringp fg))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" fg)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-all-visual-attrs ()
  "All visual attrs combined: bold+italic+underline+strikethrough+inverse+RGB fg+bg."
  ;; bold=0x01, italic=0x04, underline=0x08, strikethrough=0x100, inverse=0x40
  (let* ((flags (logior #x01 #x04 #x08 #x100 #x40))
         (props (kuro--attrs-to-face-props '(rgb . #xFFFFFF) '(rgb . #x000000) flags nil)))
    (should (eq (plist-get props :weight) 'bold))
    (should (eq (plist-get props :slant) 'italic))
    (should (plist-get props :underline))
    (should (plist-get props :strike-through))
    (should (plist-get props :inverse-video))
    (should (equal (plist-get props :foreground) "#ffffff"))
    (should (equal (plist-get props :background) "#000000"))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-no-underline-no-underline-prop ()
  "Without underline flag, :underline key is absent (nil) from result."
  (let ((props (kuro--attrs-to-face-props :default :default 0 "#ff0000")))
    ;; underline-color is provided but the underline flag bit is off.
    (should-not (plist-get props :underline))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-style2-with-color ()
  "Underline bit + style 2 (double) + color → (:color ... :style line)."
  ;; From source: style 2 with color uses 'line (same code path as style 1+color).
  (let* ((flags (logior #x08 #x400))  ; style 2 = 0x400
         (props (kuro--attrs-to-face-props :default :default flags "#667788")))
    (let ((ul (plist-get props :underline)))
      (should ul)
      (should (equal (plist-get ul :color) "#667788"))
      (should (eq (plist-get ul :style) 'line)))))

;;; Group 13: kuro--underline-style-face-symbols — data vector coverage

(ert-deftest kuro-faces-attrs--underline-style-face-symbols-is-vector ()
  (should (vectorp kuro--underline-style-face-symbols)))

(ert-deftest kuro-faces-attrs--underline-style-face-symbols-length ()
  (should (= 6 (length kuro--underline-style-face-symbols))))

(ert-deftest kuro-faces-attrs--underline-style-face-symbols-index-0-nil ()
  (should-not (aref kuro--underline-style-face-symbols 0)))

(ert-deftest kuro-faces-attrs--underline-style-face-symbols-index-1-line ()
  (should (eq 'line (aref kuro--underline-style-face-symbols 1))))

(ert-deftest kuro-faces-attrs--underline-style-face-symbols-index-2-double-line ()
  (should (eq 'double-line (aref kuro--underline-style-face-symbols 2))))

(ert-deftest kuro-faces-attrs--underline-style-face-symbols-all-styles-no-color ()
  (should-not (kuro--underline-style-to-face-prop 0 nil))
  (should (eq t (kuro--underline-style-to-face-prop 1 nil)))
  (cl-loop for style from 2 to 5
           do (let* ((result (kuro--underline-style-to-face-prop style nil))
                     (sym (plist-get result :style)))
                (should (consp result))
                (should (symbolp sym))
                (should sym))))

(provide 'kuro-faces-attrs-test-2)

;;; kuro-faces-attrs-test-2.el ends here
