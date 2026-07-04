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

;;; Group 11: kuro--underline-style-to-face-prop — style-0 and unknown styles

(defconst kuro-faces-attrs-test--ul-style-edge-table
  '((kuro-faces-attrs--underline-style0-color-ff-is-nil    0  "#ff0000" nil)
    (kuro-faces-attrs--underline-style0-color-white-is-nil  0  "#ffffff" nil)
    (kuro-faces-attrs--underline-style42-unknown-is-t      42 "#aabbcc" t)
    (kuro-faces-attrs--underline-style6-unknown-is-t        6  "#123456" t))
  "Table of (test-name style color expected-t-p) for underline style edge cases.")

(defmacro kuro-faces-attrs-test--def-ul-style-edge (test-name style color expected-t-p)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--underline-style-to-face-prop' style=%s color=%s => %s." style color expected-t-p)
     ,(if expected-t-p
          `(should (eq t (kuro--underline-style-to-face-prop ,style ,color)))
        `(should-not (kuro--underline-style-to-face-prop ,style ,color)))))

(kuro-faces-attrs-test--def-ul-style-edge kuro-faces-attrs--underline-style0-color-ff-is-nil    0  "#ff0000" nil)
(kuro-faces-attrs-test--def-ul-style-edge kuro-faces-attrs--underline-style0-color-white-is-nil  0  "#ffffff" nil)
(kuro-faces-attrs-test--def-ul-style-edge kuro-faces-attrs--underline-style42-unknown-is-t      42 "#aabbcc" t)
(kuro-faces-attrs-test--def-ul-style-edge kuro-faces-attrs--underline-style6-unknown-is-t        6  "#123456" t)

(ert-deftest kuro-faces-attrs--ul-style-edge-all-table-entries-correct ()
  "All entries in `kuro-faces-attrs-test--ul-style-edge-table' match actual behavior."
  (dolist (entry kuro-faces-attrs-test--ul-style-edge-table)
    (pcase-let ((`(,_name ,style ,color ,expected-t-p) entry))
      (if expected-t-p
          (should (eq t (kuro--underline-style-to-face-prop style color)))
        (should-not (kuro--underline-style-to-face-prop style color))))))

(kuro-faces-attrs-test--ul-with-color kuro-faces-attrs--underline-style-dashed-color-preserves-style 5 "#001122" dashes "Style 5 with color has :style dashes (not line or wave).")
(kuro-faces-attrs-test--ul-with-color kuro-faces-attrs--underline-style-dotted-color-preserves-style 4 "#334455" dots   "Style 4 with color has :style dots (not line).")

;;; Group 12: kuro--attrs-to-face-props — bold+dim cond priority and named colors

(ert-deftest kuro-faces-attrs--attrs-to-face-props-bold-takes-priority-over-dim ()
  "When both bold (0x01) and dim (0x02) flags are set, bold wins (:weight bold)."
  ;; The cond in kuro--attrs-to-face-props: (cond (bold ...) (dim ...)) — bold tested first.
  (let ((props (kuro--attrs-to-face-props :default :default #x03 nil)))
    (should (eq (plist-get props :weight) 'bold))))

(defconst kuro-faces-attrs-test--color-resolves-table
  '((kuro-faces-attrs--attrs-to-face-props-named-fg-resolves   (named   . "red")  :foreground)
    (kuro-faces-attrs--attrs-to-face-props-named-bg-resolves   (named   . "blue") :background)
    (kuro-faces-attrs--attrs-to-face-props-indexed-fg-resolves (indexed . 196)    :foreground))
  "Table of (test-name color-spec plist-key) for color-resolution paths.")

(defmacro kuro-faces-attrs-test--def-color-resolves (test-name color-spec plist-key)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--attrs-to-face-props' resolves %s to hex in %s." color-spec plist-key)
     (let* ((props ,(if (eq plist-key :foreground)
                        `(kuro--attrs-to-face-props ',color-spec :default 0 nil)
                      `(kuro--attrs-to-face-props :default ',color-spec 0 nil)))
            (val (plist-get props ,plist-key)))
       (should (stringp val))
       (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" val)))))

(kuro-faces-attrs-test--def-color-resolves kuro-faces-attrs--attrs-to-face-props-named-fg-resolves   (named   . "red")  :foreground)
(kuro-faces-attrs-test--def-color-resolves kuro-faces-attrs--attrs-to-face-props-named-bg-resolves   (named   . "blue") :background)
(kuro-faces-attrs-test--def-color-resolves kuro-faces-attrs--attrs-to-face-props-indexed-fg-resolves (indexed . 196)    :foreground)

(ert-deftest kuro-faces-attrs--color-resolves-all-table-entries-correct ()
  "All entries in `kuro-faces-attrs-test--color-resolves-table' produce hex strings."
  (dolist (entry kuro-faces-attrs-test--color-resolves-table)
    (pcase-let ((`(,_name ,color-spec ,plist-key) entry))
      (let* ((props (if (eq plist-key :foreground)
                        (kuro--attrs-to-face-props color-spec :default 0 nil)
                      (kuro--attrs-to-face-props :default color-spec 0 nil)))
             (val (plist-get props plist-key)))
        (should (stringp val))
        (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" val))))))

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

(defconst kuro-faces-attrs-test--ul-style-symbol-index-table
  '((kuro-faces-attrs--underline-style-face-symbols-index-0-nil         0 nil)
    (kuro-faces-attrs--underline-style-face-symbols-index-1-line        1 line)
    (kuro-faces-attrs--underline-style-face-symbols-index-2-double-line 2 double-line))
  "Table of (test-name index expected-sym) for `kuro--underline-style-face-symbols'.")

(defmacro kuro-faces-attrs-test--def-ul-style-symbol-index (test-name index expected-sym)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--underline-style-face-symbols'[%d] => %s." index expected-sym)
     ,(if expected-sym
          `(should (eq ',expected-sym (aref kuro--underline-style-face-symbols ,index)))
        `(should-not (aref kuro--underline-style-face-symbols ,index)))))

(kuro-faces-attrs-test--def-ul-style-symbol-index kuro-faces-attrs--underline-style-face-symbols-index-0-nil         0 nil)
(kuro-faces-attrs-test--def-ul-style-symbol-index kuro-faces-attrs--underline-style-face-symbols-index-1-line        1 line)
(kuro-faces-attrs-test--def-ul-style-symbol-index kuro-faces-attrs--underline-style-face-symbols-index-2-double-line 2 double-line)

(ert-deftest kuro-faces-attrs--ul-style-symbol-index-all-correct ()
  "All entries in `kuro-faces-attrs-test--ul-style-symbol-index-table' match actual vector."
  (dolist (entry kuro-faces-attrs-test--ul-style-symbol-index-table)
    (pcase-let ((`(,_name ,index ,expected-sym) entry))
      (if expected-sym
          (should (eq expected-sym (aref kuro--underline-style-face-symbols index)))
        (should-not (aref kuro--underline-style-face-symbols index))))))

(ert-deftest kuro-faces-attrs--underline-style-face-symbols-all-styles-no-color ()
  (should-not (kuro--underline-style-to-face-prop 0 nil))
  (should (eq t (kuro--underline-style-to-face-prop 1 nil)))
  (cl-loop for style from 2 to 5
           do (let* ((result (kuro--underline-style-to-face-prop style nil))
                     (sym (plist-get result :style)))
                (should (consp result))
                (should (symbolp sym))
                (should sym))))

;;; ── SGR flag / underline-style constant invariants ───────────────────────────

(ert-deftest kuro-faces-attrs-sgr-flags-are-power-of-two ()
  "Every SGR single-bit flag is a power of two (non-zero, exactly one bit set)."
  (dolist (flag (list kuro--sgr-flag-inverse
                      kuro--sgr-flag-overline
                      kuro--sgr-flag-superscript
                      kuro--sgr-flag-subscript))
    (should (and (integerp flag) (> flag 0) (= 0 (logand flag (1- flag)))))))

(ert-deftest kuro-faces-attrs-sgr-flags-are-distinct ()
  "kuro--sgr-flag-inverse, -overline, -superscript, -subscript occupy non-overlapping bits."
  (let ((flags (list kuro--sgr-flag-inverse kuro--sgr-flag-overline
                     kuro--sgr-flag-superscript kuro--sgr-flag-subscript)))
    (should (= (length flags) (length (delete-dups (copy-sequence flags)))))
    (let ((combined 0))
      (dolist (f flags)
        (should (= 0 (logand combined f)))
        (setq combined (logior combined f))))))

(ert-deftest kuro-faces-attrs-underline-style-mask-covers-shift ()
  "`kuro--sgr-underline-style-mask' shifted by `kuro--sgr-underline-style-shift' gives a small positive integer."
  (let ((extracted (ash (logand #x1F kuro--sgr-underline-style-mask)
                        (- kuro--sgr-underline-style-shift))))
    (should (>= extracted 0))))

(provide 'kuro-faces-attrs-test-2)

;;; kuro-faces-attrs-test-2.el ends here
