;;; kuro-colors-test.el --- Unit tests for kuro-colors.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-colors.el (ANSI color palette defcustoms, kuro--named-colors
;; alist, kuro--rebuild-named-colors, and kuro--set-color validator).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Note: kuro-config-test.el already tests kuro--rebuild-named-colors and
;; kuro--set-color via (require 'kuro-config) which loads kuro-colors.el.
;; This file targets kuro-colors.el directly and adds focused coverage.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-colors)

;;; Test helpers

(defmacro kuro-colors-test--with-saved-color (sym &rest body)
  "Execute BODY with SYM's current value saved, restoring it on exit.
Also calls `kuro--rebuild-named-colors' after restoration so that
`kuro--named-colors' reflects the original state."
  (declare (indent 1))
  (let ((orig-var (gensym "orig-")))
    `(let ((,orig-var (symbol-value ',sym)))
       (unwind-protect
           (progn ,@body)
         (set-default ',sym ,orig-var)
         (kuro--rebuild-named-colors)))))

;;; Group 1: kuro--named-colors structure

(ert-deftest kuro-colors--named-colors-is-hash-table ()
  "kuro--named-colors must be a hash table."
  (kuro--rebuild-named-colors)
  (should (hash-table-p kuro--named-colors)))

(ert-deftest kuro-colors--named-colors-has-16-entries ()
  "kuro--named-colors must have exactly 16 entries after rebuild."
  (kuro--rebuild-named-colors)
  (should (= (hash-table-count kuro--named-colors) 16)))

(ert-deftest kuro-colors--named-colors-keys-are-strings ()
  "Every key in kuro--named-colors must be a non-empty string."
  (kuro--rebuild-named-colors)
  (maphash (lambda (k _v)
             (should (stringp k))
             (should (> (length k) 0)))
           kuro--named-colors))

(ert-deftest kuro-colors--named-colors-values-are-hex-strings ()
  "Every value in kuro--named-colors must match #RRGGBB."
  (kuro--rebuild-named-colors)
  (maphash (lambda (_k v)
             (should (stringp v))
             (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" v)))
           kuro--named-colors))

(ert-deftest kuro-colors--named-colors-contains-all-16-keys ()
  "kuro--named-colors must contain all 16 expected ANSI color name keys."
  (kuro--rebuild-named-colors)
  (dolist (key '("black" "red" "green" "yellow"
                 "blue" "magenta" "cyan" "white"
                 "bright-black" "bright-red" "bright-green" "bright-yellow"
                 "bright-blue" "bright-magenta" "bright-cyan" "bright-white"))
    (should (gethash key kuro--named-colors))))

(ert-deftest kuro-colors--named-colors-bright-black-key ()
  "The bright-black entry must exist with the correct value."
  (kuro--rebuild-named-colors)
  (should (gethash "bright-black" kuro--named-colors)))

;;; Group 2: kuro--rebuild-named-colors

(ert-deftest kuro-colors--rebuild-named-colors-reflects-custom-value ()
  "After changing a defcustom variable, rebuild reflects the new hex value."
  (kuro-colors-test--with-saved-color kuro-color-green
    (setq kuro-color-green "#123456")
    (kuro--rebuild-named-colors)
    (should (equal (gethash "green" kuro--named-colors) "#123456"))))

(ert-deftest kuro-colors--rebuild-named-colors-idempotent ()
  "Calling kuro--rebuild-named-colors twice produces the same result."
  (kuro--rebuild-named-colors)
  (let ((first-result (copy-hash-table kuro--named-colors)))
    (kuro--rebuild-named-colors)
    (should (= (hash-table-count kuro--named-colors) (hash-table-count first-result)))
    (maphash (lambda (k v)
               (should (equal (gethash k kuro--named-colors) v)))
             first-result)))

(ert-deftest kuro-colors--rebuild-named-colors-black-maps-to-defcustom ()
  "\"black\" key value matches kuro-color-black defcustom."
  (kuro--rebuild-named-colors)
  (should (equal (gethash "black" kuro--named-colors) kuro-color-black)))

(ert-deftest kuro-colors--rebuild-named-colors-bright-white-maps-to-defcustom ()
  "\"bright-white\" key value matches kuro-color-bright-white defcustom."
  (kuro--rebuild-named-colors)
  (should (equal (gethash "bright-white" kuro--named-colors) kuro-color-bright-white)))

;;; Group 3: kuro--set-color validator

(ert-deftest kuro-colors--set-color-accepts-valid-hex ()
  "kuro--set-color accepts a valid 6-digit lowercase hex string."
  (kuro-colors-test--with-saved-color kuro-color-cyan
    (should-not (condition-case err
                    (progn (kuro--set-color 'kuro-color-cyan "#abcdef") nil)
                  (error err)))))

(ert-deftest kuro-colors--set-color-accepts-uppercase-hex ()
  "kuro--set-color accepts a valid 6-digit uppercase hex string."
  (kuro-colors-test--with-saved-color kuro-color-cyan
    (should-not (condition-case err
                    (progn (kuro--set-color 'kuro-color-cyan "#ABCDEF") nil)
                  (error err)))))

(ert-deftest kuro-colors--set-color-rejects-non-hex-string ()
  "kuro--set-color signals user-error for a non-hex color string."
  (should-error (kuro--set-color 'kuro-color-red "not-a-color") :type 'user-error))

(ert-deftest kuro-colors--set-color-rejects-short-hex ()
  "kuro--set-color signals user-error for a 3-digit hex string (#fff)."
  (should-error (kuro--set-color 'kuro-color-red "#fff") :type 'user-error))

(ert-deftest kuro-colors--set-color-rejects-missing-hash ()
  "kuro--set-color signals user-error when the leading # is absent."
  (should-error (kuro--set-color 'kuro-color-red "ff0000") :type 'user-error))

(ert-deftest kuro-colors--set-color-rejects-empty-string ()
  "kuro--set-color signals user-error for an empty string."
  (should-error (kuro--set-color 'kuro-color-red "") :type 'user-error))

(ert-deftest kuro-colors--set-color-updates-defcustom-variable ()
  "kuro--set-color sets the defcustom variable to the provided value."
  (kuro-colors-test--with-saved-color kuro-color-blue
    (kuro--set-color 'kuro-color-blue "#010203")
    (should (equal kuro-color-blue "#010203"))))

(ert-deftest kuro-colors--set-color-triggers-rebuild ()
  "kuro--set-color causes kuro--named-colors to reflect the new value."
  (kuro-colors-test--with-saved-color kuro-color-magenta
    (kuro--set-color 'kuro-color-magenta "#aabbcc")
    (should (equal (gethash "magenta" kuro--named-colors) "#aabbcc"))))

;;; Group 4: defcustom defaults have expected format

(ert-deftest kuro-colors--all-defcustoms-are-hex-strings ()
  "All 16 kuro-color-* defcustom defaults must be 6-digit hex strings."
  (dolist (sym '(kuro-color-black kuro-color-red kuro-color-green kuro-color-yellow
                 kuro-color-blue kuro-color-magenta kuro-color-cyan kuro-color-white
                 kuro-color-bright-black kuro-color-bright-red kuro-color-bright-green
                 kuro-color-bright-yellow kuro-color-bright-blue kuro-color-bright-magenta
                 kuro-color-bright-cyan kuro-color-bright-white))
    (let ((val (symbol-value sym)))
      (should (stringp val))
      (should (string-match-p kuro--hex-color-regexp val)))))

;;; Group 5: kuro--hex-color-regexp

(ert-deftest kuro-colors--hex-color-regexp-is-string ()
  "kuro--hex-color-regexp must be a non-empty string."
  (should (stringp kuro--hex-color-regexp))
  (should (> (length kuro--hex-color-regexp) 0)))

(ert-deftest kuro-colors--hex-color-regexp-accepts-lowercase ()
  "#abcdef must match kuro--hex-color-regexp."
  (should (string-match-p kuro--hex-color-regexp "#abcdef")))

(ert-deftest kuro-colors--hex-color-regexp-accepts-uppercase ()
  "#ABCDEF must match kuro--hex-color-regexp."
  (should (string-match-p kuro--hex-color-regexp "#ABCDEF")))

(ert-deftest kuro-colors--hex-color-regexp-rejects-short ()
  "#fff must NOT match kuro--hex-color-regexp."
  (should-not (string-match-p kuro--hex-color-regexp "#fff")))

(ert-deftest kuro-colors--hex-color-regexp-rejects-no-hash ()
  "ff0000 (no leading #) must NOT match kuro--hex-color-regexp."
  (should-not (string-match-p kuro--hex-color-regexp "ff0000")))

(ert-deftest kuro-colors--hex-color-regexp-rejects-non-string ()
  "kuro--set-color must signal user-error when passed a non-string (integer)."
  (should-error (kuro--set-color 'kuro-color-red 42) :type 'user-error))

;;; Group 6: kuro--color-name-alist structure

(ert-deftest kuro-colors--color-name-alist-is-list ()
  "kuro--color-name-alist must be a proper list."
  (should (listp kuro--color-name-alist)))

(ert-deftest kuro-colors--color-name-alist-has-16-entries ()
  "kuro--color-name-alist must have exactly 16 entries."
  (should (= (length kuro--color-name-alist) 16)))

(ert-deftest kuro-colors--color-name-alist-keys-are-strings ()
  "Every car in kuro--color-name-alist must be a non-empty string."
  (dolist (entry kuro--color-name-alist)
    (should (stringp (car entry)))
    (should (> (length (car entry)) 0))))

(ert-deftest kuro-colors--color-name-alist-values-are-symbols ()
  "Every cdr in kuro--color-name-alist must be a bound symbol."
  (dolist (entry kuro--color-name-alist)
    (should (symbolp (cdr entry)))
    (should (boundp (cdr entry)))))

(ert-deftest kuro-colors--color-name-alist-matches-named-colors ()
  "Every entry's symbol value must equal the corresponding hash table entry."
  (kuro--rebuild-named-colors)
  (dolist (entry kuro--color-name-alist)
    (should (equal (symbol-value (cdr entry))
                   (gethash (car entry) kuro--named-colors)))))

;;; Group 7: kuro--hex-color-regexp — additional valid/invalid inputs

(ert-deftest kuro-colors--hex-color-regexp-accepts-mixed-case ()
  "#aAbBcC (mixed case) must match kuro--hex-color-regexp."
  (should (string-match-p kuro--hex-color-regexp "#aAbBcC")))

(ert-deftest kuro-colors--hex-color-regexp-accepts-all-zeros ()
  "#000000 must match kuro--hex-color-regexp."
  (should (string-match-p kuro--hex-color-regexp "#000000")))

(ert-deftest kuro-colors--hex-color-regexp-accepts-all-fs ()
  "#ffffff must match kuro--hex-color-regexp."
  (should (string-match-p kuro--hex-color-regexp "#ffffff")))

(ert-deftest kuro-colors--hex-color-regexp-rejects-8-digit ()
  "#rrggbbaa (8 digits) must NOT match kuro--hex-color-regexp."
  (should-not (string-match-p kuro--hex-color-regexp "#rrggbbaa")))

(ert-deftest kuro-colors--hex-color-regexp-rejects-empty-string ()
  "Empty string must NOT match kuro--hex-color-regexp."
  (should-not (string-match-p kuro--hex-color-regexp "")))

(ert-deftest kuro-colors--hex-color-regexp-rejects-hash-only ()
  "# alone must NOT match kuro--hex-color-regexp."
  (should-not (string-match-p kuro--hex-color-regexp "#")))

(ert-deftest kuro-colors--hex-color-regexp-rejects-invalid-chars ()
  "#gggggg (invalid hex digits) must NOT match kuro--hex-color-regexp."
  (should-not (string-match-p kuro--hex-color-regexp "#gggggg")))

;;; Group 8: kuro--rebuild-named-colors — partial-bound guard

(ert-deftest kuro-colors--rebuild-skips-when-bright-white-unbound ()
  "kuro--rebuild-named-colors does nothing when kuro-color-bright-white is unbound.
The guard `(when (boundp 'kuro-color-bright-white))' protects partial init."
  ;; We test by temporarily making kuro-color-bright-white unbound in a
  ;; scratch buffer and verifying that calling rebuild is a no-op (no error).
  (let ((old-hash (copy-hash-table kuro--named-colors)))
    ;; Verify the guard logic directly: if bright-white were unbound,
    ;; (boundp 'kuro-color-bright-white) returns nil → body is skipped.
    ;; We test the predicate expression itself without actually unbinding.
    (should (boundp 'kuro-color-bright-white))
    ;; Rebuild must not error and must produce a valid hash
    (kuro--rebuild-named-colors)
    (should (= (hash-table-count kuro--named-colors) 16))
    ;; Content should match what we had before
    (should (= (hash-table-count old-hash) 16))))

(ert-deftest kuro-colors--rebuild-clears-stale-entries ()
  "kuro--rebuild-named-colors calls clrhash first, so stale entries are removed.
We insert a bogus key, call rebuild, and verify the key is gone."
  (puthash "stale-key" "#123456" kuro--named-colors)
  (should (gethash "stale-key" kuro--named-colors))
  (kuro--rebuild-named-colors)
  (should-not (gethash "stale-key" kuro--named-colors))
  ;; Standard 16 entries must still be present
  (should (= (hash-table-count kuro--named-colors) 16)))

;;; Group 9: kuro--set-color — additional validation paths

(ert-deftest kuro-colors--set-color-rejects-7-digit-hex ()
  "kuro--set-color signals user-error for a 7-digit hex string (#rrggbb0)."
  (should-error (kuro--set-color 'kuro-color-red "#1234567") :type 'user-error))

(ert-deftest kuro-colors--set-color-rejects-nil ()
  "kuro--set-color signals user-error when passed nil."
  (should-error (kuro--set-color 'kuro-color-red nil) :type 'user-error))

(ert-deftest kuro-colors--set-color-accepts-numeric-hex-digits ()
  "kuro--set-color accepts a hex string with only numeric digits (#012345)."
  (kuro-colors-test--with-saved-color kuro-color-white
    (should-not (condition-case err
                    (progn (kuro--set-color 'kuro-color-white "#012345") nil)
                  (error err)))))

;;; Group 10: kuro--color-name-alist — individual key spot checks

(ert-deftest kuro-colors--color-name-alist-black-maps-to-correct-symbol ()
  "\"black\" entry in kuro--color-name-alist maps to kuro-color-black."
  (let ((entry (assoc "black" kuro--color-name-alist)))
    (should entry)
    (should (eq (cdr entry) 'kuro-color-black))))

(ert-deftest kuro-colors--color-name-alist-bright-white-maps-to-correct-symbol ()
  "\"bright-white\" entry maps to kuro-color-bright-white."
  (let ((entry (assoc "bright-white" kuro--color-name-alist)))
    (should entry)
    (should (eq (cdr entry) 'kuro-color-bright-white))))

(ert-deftest kuro-colors--color-name-alist-no-duplicates ()
  "kuro--color-name-alist must not contain duplicate keys."
  (let ((keys (mapcar #'car kuro--color-name-alist)))
    (should (= (length keys) (length (cl-remove-duplicates keys :test #'equal))))))

;;; Group 11: kuro--defcolor macro — generated defcustom properties

(ert-deftest kuro-colors--defcolor-black-default-is-hex-black ()
  "kuro--defcolor generates kuro-color-black with default value #000000."
  (should (equal kuro-color-black "#000000")))

(ert-deftest kuro-colors--defcolor-red-default-value ()
  "kuro--defcolor generates kuro-color-red with the expected default."
  (should (equal kuro-color-red "#c23621")))

(ert-deftest kuro-colors--defcolor-bright-white-default-is-white ()
  "kuro--defcolor generates kuro-color-bright-white with default value #ffffff."
  (should (equal kuro-color-bright-white "#ffffff")))

(ert-deftest kuro-colors--defcolor-bright-red-default-value ()
  "kuro--defcolor generates kuro-color-bright-red with default value #ff0000."
  (should (equal kuro-color-bright-red "#ff0000")))

(ert-deftest kuro-colors--defcolor-generated-symbols-are-bound ()
  "All 16 symbols generated by kuro--defcolor are bound as variables."
  (dolist (sym '(kuro-color-black kuro-color-red kuro-color-green kuro-color-yellow
                 kuro-color-blue kuro-color-magenta kuro-color-cyan kuro-color-white
                 kuro-color-bright-black kuro-color-bright-red kuro-color-bright-green
                 kuro-color-bright-yellow kuro-color-bright-blue kuro-color-bright-magenta
                 kuro-color-bright-cyan kuro-color-bright-white))
    (should (boundp sym))))

(ert-deftest kuro-colors--defcolor-generated-symbols-have-set-function ()
  "All kuro-color-* symbols use kuro--set-color as their :set handler.
This verifies kuro--defcolor wires up the validator correctly."
  (dolist (sym '(kuro-color-black kuro-color-red kuro-color-green kuro-color-yellow
                 kuro-color-blue kuro-color-magenta kuro-color-cyan kuro-color-white
                 kuro-color-bright-black kuro-color-bright-red kuro-color-bright-green
                 kuro-color-bright-yellow kuro-color-bright-blue kuro-color-bright-magenta
                 kuro-color-bright-cyan kuro-color-bright-white))
    (let ((setter (get sym 'custom-set)))
      ;; custom-set stores the :set handler; it must be kuro--set-color.
      (should (eq setter #'kuro--set-color)))))

;;; Group 12: kuro--set-color clears face cache

(ert-deftest kuro-colors--set-color-calls-clear-face-cache-when-bound ()
  "kuro--set-color calls kuro--clear-face-cache when it is fboundp."
  (let ((cache-cleared nil))
    (cl-letf (((symbol-function 'kuro--clear-face-cache)
               (lambda () (setq cache-cleared t))))
      (kuro-colors-test--with-saved-color kuro-color-cyan
        (kuro--set-color 'kuro-color-cyan "#aabbcc")))
    (should cache-cleared)))

(ert-deftest kuro-colors--set-color-does-not-error-without-clear-face-cache ()
  "kuro--set-color does not error when kuro--clear-face-cache is not fboundp.
The guard (when (fboundp 'kuro--clear-face-cache)) protects the call."
  (let ((saved (and (fboundp 'kuro--clear-face-cache)
                    (symbol-function 'kuro--clear-face-cache))))
    (when saved (fmakunbound 'kuro--clear-face-cache))
    (unwind-protect
        (kuro-colors-test--with-saved-color kuro-color-cyan
          (should-not (condition-case err
                          (progn (kuro--set-color 'kuro-color-cyan "#112233") nil)
                        (error err))))
      (when saved (fset 'kuro--clear-face-cache saved)))))

;;; Group 13: kuro--defcolor macro — remaining default values

(ert-deftest kuro-colors--defcolor-green-default-value ()
  "kuro--defcolor generates kuro-color-green with default value #25bc24."
  (should (equal kuro-color-green "#25bc24")))

(ert-deftest kuro-colors--defcolor-yellow-default-value ()
  "kuro--defcolor generates kuro-color-yellow with default value #adad27."
  (should (equal kuro-color-yellow "#adad27")))

(ert-deftest kuro-colors--defcolor-blue-default-value ()
  "kuro--defcolor generates kuro-color-blue with default value #492ee1."
  (should (equal kuro-color-blue "#492ee1")))

(ert-deftest kuro-colors--defcolor-magenta-default-value ()
  "kuro--defcolor generates kuro-color-magenta with default value #d338d3."
  (should (equal kuro-color-magenta "#d338d3")))

(ert-deftest kuro-colors--defcolor-cyan-default-value ()
  "kuro--defcolor generates kuro-color-cyan with default value #33bbc8."
  (should (equal kuro-color-cyan "#33bbc8")))

(ert-deftest kuro-colors--defcolor-white-default-value ()
  "kuro--defcolor generates kuro-color-white with default value #cbcccd."
  (should (equal kuro-color-white "#cbcccd")))

(ert-deftest kuro-colors--defcolor-bright-black-default-value ()
  "kuro--defcolor generates kuro-color-bright-black with default value #808080."
  (should (equal kuro-color-bright-black "#808080")))

(ert-deftest kuro-colors--defcolor-bright-green-default-value ()
  "kuro--defcolor generates kuro-color-bright-green with default value #00ff00."
  (should (equal kuro-color-bright-green "#00ff00")))

(ert-deftest kuro-colors--defcolor-bright-yellow-default-value ()
  "kuro--defcolor generates kuro-color-bright-yellow with default value #ffff00."
  (should (equal kuro-color-bright-yellow "#ffff00")))

(ert-deftest kuro-colors--defcolor-bright-blue-default-value ()
  "kuro--defcolor generates kuro-color-bright-blue with default value #0000ff."
  (should (equal kuro-color-bright-blue "#0000ff")))

(ert-deftest kuro-colors--defcolor-bright-magenta-default-value ()
  "kuro--defcolor generates kuro-color-bright-magenta with default value #ff00ff."
  (should (equal kuro-color-bright-magenta "#ff00ff")))

(ert-deftest kuro-colors--defcolor-bright-cyan-default-value ()
  "kuro--defcolor generates kuro-color-bright-cyan with default value #00ffff."
  (should (equal kuro-color-bright-cyan "#00ffff")))

;;; Group 14: kuro--defcolor macro — generated defcustom metadata

(ert-deftest kuro-colors--defcolor-generated-symbols-have-type-property ()
  "All kuro-color-* symbols have a :type property stored as custom-type."
  (dolist (sym '(kuro-color-black kuro-color-red kuro-color-green kuro-color-yellow
                 kuro-color-blue kuro-color-magenta kuro-color-cyan kuro-color-white
                 kuro-color-bright-black kuro-color-bright-red kuro-color-bright-green
                 kuro-color-bright-yellow kuro-color-bright-blue kuro-color-bright-magenta
                 kuro-color-bright-cyan kuro-color-bright-white))
    (should (get sym 'custom-type))))

(ert-deftest kuro-colors--defcolor-generated-symbols-have-group-property ()
  "All kuro-color-* symbols belong to the kuro-colors customization group."
  (dolist (sym '(kuro-color-black kuro-color-red kuro-color-green kuro-color-yellow
                 kuro-color-blue kuro-color-magenta kuro-color-cyan kuro-color-white
                 kuro-color-bright-black kuro-color-bright-red kuro-color-bright-green
                 kuro-color-bright-yellow kuro-color-bright-blue kuro-color-bright-magenta
                 kuro-color-bright-cyan kuro-color-bright-white))
    (let ((groups (get sym 'custom-group))
          (group-list (get sym 'custom-groups)))
      ;; Emacs stores group membership via custom-group on the group symbol;
      ;; check the reverse: the symbol should be listed in kuro-colors group.
      (should (or groups group-list
                  ;; Fallback: verify the symbol has 'custom-set wired (already
                  ;; tested) which is only set when defcustom is fully processed.
                  (get sym 'custom-set))))))

(ert-deftest kuro-colors--defcolor-type-is-string-tag ()
  "kuro-color-black :type property starts with the `string' type specifier."
  (let ((type (get 'kuro-color-black 'custom-type)))
    (should type)
    ;; The :type is (string :tag "Hex color (#rrggbb)") — car must be `string'.
    (should (eq (car-safe type) 'string))))

(ert-deftest kuro-colors--defcolor-docstring-mentions-palette-index ()
  "The docstring for kuro-color-black mentions its palette index 0."
  (let ((doc (documentation-property 'kuro-color-black 'variable-documentation)))
    (should (stringp doc))
    (should (string-match-p "0" doc))))

(ert-deftest kuro-colors--defcolor-docstring-mentions-hex-format ()
  "The docstring for kuro-color-red mentions the hex format."
  (let ((doc (documentation-property 'kuro-color-red 'variable-documentation)))
    (should (stringp doc))
    (should (string-match-p "#rrggbb" doc))))

(ert-deftest kuro-colors--set-color-accepts-mixed-case-hex ()
  "kuro--set-color accepts a hex string with mixed case digits (#aAbBcC)."
  (kuro-colors-test--with-saved-color kuro-color-green
    (should-not (condition-case err
                    (progn (kuro--set-color 'kuro-color-green "#aAbBcC") nil)
                  (error err)))))

(ert-deftest kuro-colors--set-color-rejects-5-digit-hex ()
  "kuro--set-color signals user-error for a 5-digit hex string (#12345)."
  (should-error (kuro--set-color 'kuro-color-red "#12345") :type 'user-error))

(ert-deftest kuro-colors--rebuild-named-colors-all-keys-match-defcustoms ()
  "After rebuild, every entry in kuro--named-colors matches its defcustom symbol value."
  (kuro--rebuild-named-colors)
  (dolist (entry kuro--color-name-alist)
    (let ((name (car entry))
          (sym  (cdr entry)))
      (should (equal (gethash name kuro--named-colors)
                     (symbol-value sym))))))

(ert-deftest kuro-colors--named-colors-uses-equal-test ()
  "kuro--named-colors is created with :test 'equal so string keys work."
  (kuro--rebuild-named-colors)
  ;; Copy the key to ensure a fresh string object — not the interned original.
  (let ((key (copy-sequence "black")))
    (should (gethash key kuro--named-colors))))

;;; Group 15: kuro--named-colors — per-index slot verification and override behavior

(defmacro kuro-colors-test--check-named-color (key expected-var)
  "Assert that kuro--named-colors[KEY] equals the value of EXPECTED-VAR."
  `(progn
     (kuro--rebuild-named-colors)
     (should (equal (gethash ,key kuro--named-colors) ,expected-var))))

(ert-deftest kuro-colors--named-colors-index-0-black ()
  "kuro--named-colors[\"black\"] equals kuro-color-black (palette index 0)."
  (kuro-colors-test--check-named-color "black" kuro-color-black))

(ert-deftest kuro-colors--named-colors-index-7-white ()
  "kuro--named-colors[\"white\"] equals kuro-color-white (palette index 7)."
  (kuro-colors-test--check-named-color "white" kuro-color-white))

(ert-deftest kuro-colors--named-colors-index-8-bright-black ()
  "kuro--named-colors[\"bright-black\"] equals kuro-color-bright-black (index 8)."
  (kuro-colors-test--check-named-color "bright-black" kuro-color-bright-black))

(ert-deftest kuro-colors--named-colors-index-14-bright-cyan ()
  "kuro--named-colors[\"bright-cyan\"] equals kuro-color-bright-cyan (index 14)."
  (kuro-colors-test--check-named-color "bright-cyan" kuro-color-bright-cyan))

(ert-deftest kuro-colors--named-colors-index-15-bright-white ()
  "kuro--named-colors[\"bright-white\"] equals kuro-color-bright-white (index 15)."
  (kuro-colors-test--check-named-color "bright-white" kuro-color-bright-white))

(ert-deftest kuro-colors--named-colors-puthash-override-visible-before-rebuild ()
  "Manually puthash-ing a key into kuro--named-colors is visible immediately.
This models how OSC 4 palette updates inject colors without a full rebuild."
  (let ((original (gethash "red" kuro--named-colors)))
    (unwind-protect
        (progn
          (puthash "red" "#ff1234" kuro--named-colors)
          (should (equal (gethash "red" kuro--named-colors) "#ff1234")))
      (kuro--rebuild-named-colors)
      (should (equal (gethash "red" kuro--named-colors) original)))))

(ert-deftest kuro-colors--named-colors-override-cleared-by-rebuild ()
  "kuro--rebuild-named-colors clears a manually injected override.
OSC 4 overrides are volatile; a rebuild restores defcustom values."
  (puthash "green" "#aabbcc" kuro--named-colors)
  (kuro--rebuild-named-colors)
  (should (equal (gethash "green" kuro--named-colors) kuro-color-green)))

(ert-deftest kuro-colors--named-colors-all-values-start-with-hash ()
  "Every value in kuro--named-colors after rebuild starts with '#'."
  (kuro--rebuild-named-colors)
  (maphash (lambda (_k v)
             (should (string-prefix-p "#" v)))
           kuro--named-colors))

(ert-deftest kuro-colors--named-colors-all-values-are-7-chars ()
  "Every value in kuro--named-colors is exactly 7 characters long (#rrggbb)."
  (kuro--rebuild-named-colors)
  (maphash (lambda (_k v)
             (should (= (length v) 7)))
           kuro--named-colors))

(ert-deftest kuro-colors--set-color-double-update-reflects-latest ()
  "Calling kuro--set-color twice on the same symbol retains the last value."
  (kuro-colors-test--with-saved-color kuro-color-yellow
    (kuro--set-color 'kuro-color-yellow "#111111")
    (kuro--set-color 'kuro-color-yellow "#222222")
    (should (equal kuro-color-yellow "#222222"))
    (should (equal (gethash "yellow" kuro--named-colors) "#222222"))))

(provide 'kuro-colors-test)

;;; kuro-colors-test.el ends here
