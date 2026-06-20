;;; kuro-input-keymap-test-5.el --- Tests for kuro-input-keymap.el — Groups 5-9  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keymap-test-support)

;;; Group 5: Modifier+arrow xterm CSI sequences

(defmacro kuro-keymap-test--modifier-arrow-seq (mod-sym arrow-sym)
  "Return the sequence the keymap binding for MOD-SYM+ARROW-SYM would send.
Calls the binding function with the shared KKP capture helper and
returns the last string sent by `kuro--send-key'."
  `(let* ((map (kuro-keymap-test--built-map))
          (event (intern (format "%s-%s" ',mod-sym ',arrow-sym)))
          (binding (lookup-key map (vector event))))
     (should (functionp binding))
     (kuro-input-keymap-test--with-kkp nil
       (funcall binding))))

(eval-and-compile
  (defconst kuro-input-keymap-test--modifier-arrow-table
    '((kuro-input-keymap-shift-up-sends-csi-1-2A   S up    "\e[1;2A")
      (kuro-input-keymap-ctrl-right-sends-csi-1-5C C right "\e[1;5C")
      (kuro-input-keymap-meta-down-sends-csi-1-3B  M down  "\e[1;3B")
      (kuro-input-keymap-ctrl-left-sends-csi-1-5D  C left  "\e[1;5D")
      (kuro-input-keymap-shift-down-sends-csi-1-2B S down  "\e[1;2B")
      (kuro-input-keymap-meta-right-sends-csi-1-3C M right "\e[1;3C"))
    "Table of (test-name modifier direction expected-csi) for modifier+arrow xterm sequences."))

(defmacro kuro-input-keymap-test--def-modifier-arrow (test-name mod dir expected)
  `(ert-deftest ,test-name ()
     ,(format "%s-%s sends %S." mod dir expected)
     (should (equal (kuro-keymap-test--modifier-arrow-seq ,mod ,dir) ,expected))))

(defmacro kuro-input-keymap-test--deftest-modifier-arrows ()
  "Define modifier+arrow tests from `kuro-input-keymap-test--modifier-arrow-table'."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,mod ,dir ,expected) entry))
            `(kuro-input-keymap-test--def-modifier-arrow
              ,test-name ,mod ,dir ,expected)))
        kuro-input-keymap-test--modifier-arrow-table)))

(kuro-input-keymap-test--deftest-modifier-arrows)

(ert-deftest kuro-input-keymap-test--all-modifier-arrows-send-correct-csi ()
  "All kuro-input-keymap-test--modifier-arrow-table entries send the expected CSI sequence."
  (kuro-input-keymap-test--each-entry
   kuro-input-keymap-test--modifier-arrow-table
   (lambda (entry)
     (pcase-let ((`(,_name ,mod ,dir ,expected) entry))
       (let* ((map (kuro-keymap-test--built-map))
              (event (intern (format "%s-%s" mod dir)))
              (binding (lookup-key map (vector event))))
         (should (functionp binding))
         (should (equal (kuro-input-keymap-test--with-kkp nil
                          (funcall binding))
                        expected)))))))


;;; Group 6: Yank remaps

(eval-and-compile
  (defconst kuro-input-keymap-test--yank-remap-table
    '((kuro-input-keymap-build-has-yank-remap           yank           kuro--yank)
      (kuro-input-keymap-build-has-yank-pop-remap       yank-pop       kuro--yank-pop)
      (kuro-input-keymap-build-has-clipboard-yank-remap clipboard-yank kuro--yank))
    "Table of (test-name orig-fn remap-fn) for yank-family remap assertions."))

(defmacro kuro-input-keymap-test--def-yank-remap (test-name orig-fn remap-fn)
  `(ert-deftest ,test-name ()
     ,(format "Built keymap remaps `%s' to `%s'." orig-fn remap-fn)
     (let ((map (kuro-keymap-test--built-map)))
       (should (eq (lookup-key map [remap ,orig-fn]) #',remap-fn)))))

(defmacro kuro-input-keymap-test--deftest-yank-remaps ()
  "Define yank remap tests from `kuro-input-keymap-test--yank-remap-table'."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,orig-fn ,remap-fn) entry))
            `(kuro-input-keymap-test--def-yank-remap
              ,test-name ,orig-fn ,remap-fn)))
        kuro-input-keymap-test--yank-remap-table)))

(kuro-input-keymap-test--deftest-yank-remaps)

(ert-deftest kuro-input-keymap-test--all-yank-remaps-correct ()
  "All kuro-input-keymap-test--yank-remap-table entries are wired correctly."
  (let ((map (kuro-keymap-test--built-map)))
    (kuro-input-keymap-test--each-entry
     kuro-input-keymap-test--yank-remap-table
     (lambda (entry)
       (pcase-let ((`(,_name ,orig-fn ,remap-fn) entry))
         (should (eq (lookup-key map (vector 'remap orig-fn)) remap-fn)))))))

(ert-deftest kuro-input-keymap-clipboard-yank-remap-sends-kill-ring-text ()
  "Invoking the [remap clipboard-yank] binding sends kill-ring text via kuro--send-key."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map [remap clipboard-yank]))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      (let* ((kill-ring (list "clipboard-text"))
             (kill-ring-yank-pointer kill-ring)
             (kuro--bracketed-paste-mode nil))
        (funcall binding)))
    (should (equal sent '("clipboard-text")))))

;;; Group 7: kuro--meta-punct-bindings table

(ert-deftest kuro-input-keymap-meta-punct-has-6-entries ()
  "kuro--meta-punct-bindings contains exactly 6 entries."
  (should (= (length kuro--meta-punct-bindings) 6)))

(ert-deftest kuro-input-keymap-meta-punct-entries-are-cons-pairs ()
  "Every entry in kuro--meta-punct-bindings is a (STRING . INTEGER) cons pair."
  (kuro-input-keymap-test--each-entry
   kuro--meta-punct-bindings
   (lambda (entry)
     (should (consp entry))
     (should (stringp (car entry)))
     (should (integerp (cdr entry))))))

(eval-and-compile
  (defconst kuro-input-keymap-test--meta-punct-spot-table
    '((kuro-input-keymap-meta-punct-spot-check-dot       "M-." ?.)
      (kuro-input-keymap-meta-punct-spot-check-slash      "M-/" ?/)
      (kuro-input-keymap-meta-punct-spot-check-underscore "M-_" ?_))
    "Table of (test-name key-str char) for kuro--meta-punct-bindings spot checks."))

(defmacro kuro-input-keymap-test--def-meta-punct-spot (test-name key-str char)
  `(ert-deftest ,test-name ()
     ,(format "kuro--meta-punct-bindings: %S → ?%c." key-str char)
     (should (= (cdr (assoc ,key-str kuro--meta-punct-bindings)) ,char))))

(defmacro kuro-input-keymap-test--deftest-meta-punct-spots ()
  "Define meta punctuation spot tests from `kuro-input-keymap-test--meta-punct-spot-table'."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,key-str ,char) entry))
            `(kuro-input-keymap-test--def-meta-punct-spot
              ,test-name ,key-str ,char)))
        kuro-input-keymap-test--meta-punct-spot-table)))

(kuro-input-keymap-test--deftest-meta-punct-spots)

(ert-deftest kuro-input-keymap-test--all-meta-punct-spots-correct ()
  "All kuro-input-keymap-test--meta-punct-spot-table entries map to the expected char."
  (kuro-input-keymap-test--each-entry
   kuro-input-keymap-test--meta-punct-spot-table
   (lambda (entry)
     (pcase-let ((`(,_name ,key-str ,char) entry))
       (should (= (cdr (assoc key-str kuro--meta-punct-bindings)) char))))))

(ert-deftest kuro-input-keymap-meta-punct-no-alphanumeric ()
  "kuro--meta-punct-bindings contains no alphabetic or digit character bindings."
  (kuro-input-keymap-test--each-entry
   kuro--meta-punct-bindings
   (lambda (entry)
     (let ((c (cdr entry)))
       (should-not (or (<= ?a c ?z) (<= ?A c ?Z) (<= ?0 c ?9)))))))

;; --- kuro--meta-letter-chars table ---

(ert-deftest kuro-input-keymap-meta-letter-chars-has-62-entries ()
  "kuro--meta-letter-chars contains all letters and digits."
  (should (= (length kuro--meta-letter-chars) 62)))

(ert-deftest kuro-input-keymap-meta-letter-chars-entries-are-chars ()
  "Every entry in kuro--meta-letter-chars is a character."
  (kuro-input-keymap-test--each-entry
   kuro--meta-letter-chars
   (lambda (entry)
     (should (characterp entry)))))

(ert-deftest kuro-input-keymap-meta-letter-chars-cover-ranges ()
  "kuro--meta-letter-chars covers the expected a-z, A-Z, and 0-9 ranges."
  (should (eq (car kuro--meta-letter-chars) ?a))
  (should (eq (nth 25 kuro--meta-letter-chars) ?z))
  (should (eq (nth 26 kuro--meta-letter-chars) ?A))
  (should (eq (nth 51 kuro--meta-letter-chars) ?Z))
  (should (eq (nth 52 kuro--meta-letter-chars) ?0))
  (should (eq (car (last kuro--meta-letter-chars)) ?9))
  (let ((chars (copy-sequence kuro--meta-letter-chars)))
    (should (= (length chars)
               (length (delete-dups chars))))))


;;; Group 8: kuro--nav-key-bindings and kuro--mouse-bindings tables

(ert-deftest kuro-input-keymap-nav-bindings-has-13-entries ()
  "kuro--nav-key-bindings contains exactly 13 entries."
  (should (= (length kuro--nav-key-bindings) 13)))

(ert-deftest kuro-input-keymap-nav-bindings-entries-are-cons-pairs ()
  "Every entry in kuro--nav-key-bindings is a (VECTOR . SYMBOL) cons pair."
  (kuro-input-keymap-test--each-entry
   kuro--nav-key-bindings
   (lambda (entry)
     (should (consp entry))
     (should (vectorp (car entry)))
     (should (symbolp (cdr entry))))))

(ert-deftest kuro-input-keymap-nav-bindings-spot-check-home ()
  "[home] maps to kuro--HOME in kuro--nav-key-bindings."
  (should (eq (cdr (assoc [home] kuro--nav-key-bindings)) 'kuro--HOME)))

(ert-deftest kuro-input-keymap-nav-bindings-spot-check-s-prior ()
  "[S-prior] maps to kuro-scroll-up in kuro--nav-key-bindings."
  (should (eq (cdr (assoc [S-prior] kuro--nav-key-bindings)) 'kuro-scroll-up)))

(ert-deftest kuro-input-keymap-mouse-bindings-has-8-entries ()
  "kuro--mouse-bindings contains exactly 8 entries."
  (should (= (length kuro--mouse-bindings) 8)))

(ert-deftest kuro-input-keymap-mouse-bindings-entries-are-cons-pairs ()
  "Every entry in kuro--mouse-bindings is a (VECTOR . SYMBOL) cons pair."
  (kuro-input-keymap-test--each-entry
   kuro--mouse-bindings
   (lambda (entry)
     (should (consp entry))
     (should (vectorp (car entry)))
     (should (symbolp (cdr entry))))))

(ert-deftest kuro-input-keymap-mouse-bindings-spot-check-mouse-4 ()
  "[mouse-4] maps to kuro--mouse-scroll-up in kuro--mouse-bindings."
  (should (eq (cdr (assoc [mouse-4] kuro--mouse-bindings)) 'kuro--mouse-scroll-up)))

(ert-deftest kuro-input-keymap-mouse-bindings-down-mouse-count ()
  "kuro--mouse-bindings has exactly 3 down-mouse entries."
  (let ((count (cl-count-if (lambda (e) (string-prefix-p "down-mouse"
                                                         (symbol-name (aref (car e) 0))))
                            kuro--mouse-bindings)))
    (should (= count 3))))

(ert-deftest kuro-input-keymap-build-has-home-end-bindings ()
  "[home] and [end] are bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [home]))
    (should (lookup-key map [end]))))

(ert-deftest kuro-input-keymap-build-has-page-bindings ()
  "[prior] (Page Up) and [next] (Page Down) are bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [prior]))
    (should (lookup-key map [next]))))

(ert-deftest kuro-input-keymap-build-has-fkey-bindings ()
  "F1 through F12 are all bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (kuro-input-keymap-test--each-entry
     '([f1] [f2] [f3] [f4] [f5] [f6]
       [f7] [f8] [f9] [f10] [f11] [f12])
     (lambda (fkey)
       (should (lookup-key map fkey))))))

(ert-deftest kuro-input-keymap-build-has-meta-punct-bindings ()
  "M-. M-< M-> M-? M-/ M-_ are all bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (kuro-input-keymap-test--each-entry
     kuro--meta-punct-bindings
     (lambda (entry)
       (should (lookup-key map (kbd (car entry))))))))


;;; Group 9: kuro--fkey-handlers table

(ert-deftest kuro-input-keymap-fkey-handlers-has-12-entries ()
  "kuro--fkey-handlers contains exactly 12 entries (F1-F12)."
  (should (= (length kuro--fkey-handlers) 12)))

(ert-deftest kuro-input-keymap-fkey-handlers-entries-are-cons-pairs ()
  "Every entry in kuro--fkey-handlers is a (SYMBOL . SYMBOL) cons pair."
  (kuro-input-keymap-test--each-entry
   kuro--fkey-handlers
   (lambda (entry)
     (should (consp entry))
     (should (symbolp (car entry)))
     (should (symbolp (cdr entry))))))

(ert-deftest kuro-input-keymap-fkey-handlers-spot-check-f1 ()
  "f1 maps to kuro--F1 in kuro--fkey-handlers."
  (should (eq (cdr (assq 'f1 kuro--fkey-handlers)) 'kuro--F1)))

(ert-deftest kuro-input-keymap-fkey-handlers-spot-check-f12 ()
  "f12 maps to kuro--F12 in kuro--fkey-handlers."
  (should (eq (cdr (assq 'f12 kuro--fkey-handlers)) 'kuro--F12)))

(ert-deftest kuro-input-keymap-fkey-handlers-all-keys-are-fN ()
  "All key symbols in kuro--fkey-handlers match the pattern fN (f1-f12)."
  (kuro-input-keymap-test--each-entry
   kuro--fkey-handlers
   (lambda (entry)
     (should (string-match-p "\\`f[0-9]+\\'" (symbol-name (car entry)))))))


(provide 'kuro-input-keymap-test-5)
;;; kuro-input-keymap-test-5.el ends here
