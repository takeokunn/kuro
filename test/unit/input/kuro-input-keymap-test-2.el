;;; kuro-input-keymap-test-2.el --- Tests for kuro-input-keymap.el (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keymap-test-support)

;; The generated tests below keep each case independent while removing the
;; repeated setup boilerplate from the more mechanical bindings checks.

(eval-and-compile
  (defconst kuro-input-keymap-test-2--lookup-eq-cases
    '((kuro-input-keymap-s-prior-bound-to-scroll-up
       "[S-prior] is bound to `kuro-scroll-up' in the built keymap."
       (kuro-input-keymap-test--with-built-map map map)
       [S-prior]
       #'kuro-scroll-up)
      (kuro-input-keymap-s-next-bound-to-scroll-down
       "[S-next] is bound to `kuro-scroll-down' in the built keymap."
       (kuro-input-keymap-test--with-built-map map map)
       [S-next]
       #'kuro-scroll-down)
      (kuro-input-keymap-s-end-bound-to-scroll-bottom
       "[S-end] is bound to `kuro-scroll-bottom' in the built keymap."
       (kuro-input-keymap-test--with-built-map map map)
       [S-end]
       #'kuro-scroll-bottom)
      (kuro-input-keymap-setup-special-return-bound
       "`kuro--keymap-setup-special' binds [return] to `kuro--RET'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-special km)
       [return]
       #'kuro--RET)
      (kuro-input-keymap-setup-special-c-m-bound
       "`kuro--keymap-setup-special' binds C-m to `kuro--RET'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-special km)
       (kbd "C-m")
       #'kuro--RET)
      (kuro-input-keymap-setup-special-tab-bound
       "`kuro--keymap-setup-special' binds [tab] to `kuro--TAB'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-special km)
       [tab]
       #'kuro--TAB)
      (kuro-input-keymap-setup-special-c-i-bound
       "`kuro--keymap-setup-special' binds C-i to `kuro--TAB'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-special km)
       (kbd "C-i")
       #'kuro--TAB)
      (kuro-input-keymap-setup-special-backspace-bound
       "`kuro--keymap-setup-special' binds [backspace] to `kuro--DEL'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-special km)
       [backspace]
       #'kuro--DEL)
      (kuro-input-keymap-setup-special-c-h-bound
       "`kuro--keymap-setup-special' binds C-h to `kuro--DEL'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-special km)
       (kbd "C-h")
       #'kuro--DEL)
      (kuro-input-keymap-setup-special-del-bound
       "`kuro--keymap-setup-special' binds DEL to `kuro--DEL'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-special km)
       (kbd "DEL")
       #'kuro--DEL)
      (kuro-input-keymap-setup-ctrl-c-v-bound-to-scroll-aware
       "`kuro--keymap-setup-ctrl' binds C-v to `kuro--scroll-aware-ctrl-v'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-ctrl km)
       (kbd "C-v")
       #'kuro--scroll-aware-ctrl-v)
      (kuro-input-keymap-setup-meta-m-v-bound-to-scroll-aware
       "`kuro--keymap-setup-meta' binds M-v to `kuro--scroll-aware-meta-v'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-v")
       #'kuro--scroll-aware-meta-v)
      (kuro-input-keymap-setup-meta-esc-v-fallback-bound-to-scroll-aware
       "`kuro--keymap-setup-meta' binds [\\e ?v] two-key fallback to `kuro--scroll-aware-meta-v'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (vector ?\e ?v)
       #'kuro--scroll-aware-meta-v)
      (kuro-input-keymap-setup-meta-m-del-bound-to-meta-backspace
       "`kuro--keymap-setup-meta' binds M-DEL to `kuro--send-meta-backspace'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-DEL")
       #'kuro--send-meta-backspace)
      (kuro-input-keymap-setup-meta-m-backspace-bound-to-meta-backspace
       "`kuro--keymap-setup-meta' binds M-<backspace> to `kuro--send-meta-backspace'."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-<backspace>")
       #'kuro--send-meta-backspace))
    "Table-driven `lookup-key' assertions that expect an exact binding."))

(eval-and-compile
  (defconst kuro-input-keymap-test-2--lookup-live-cases
    '((kuro-input-keymap-insert-key-is-bound
       "[insert] is bound in the built keymap."
       (kuro-input-keymap-test--with-built-map map map)
       [insert])
      (kuro-input-keymap-delete-key-is-bound
       "[delete] is bound in the built keymap."
       (kuro-input-keymap-test--with-built-map map map)
       [delete])
      (kuro-input-keymap-setup-meta-m-a-bound
       "`kuro--keymap-setup-meta' binds M-a."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-a"))
      (kuro-input-keymap-setup-meta-m-z-bound
       "`kuro--keymap-setup-meta' binds M-z."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-z"))
      (kuro-input-keymap-setup-meta-m-uppercase-bound
       "`kuro--keymap-setup-meta' binds M-A and M-Z (uppercase range)."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-A"))
      (kuro-input-keymap-setup-meta-m-uppercase-z-bound
       "`kuro--keymap-setup-meta' binds M-A and M-Z (uppercase range)."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-Z"))
      (kuro-input-keymap-setup-meta-m-digit-0-bound
       "`kuro--keymap-setup-meta' binds M-0 and M-9 (digit range)."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-0"))
      (kuro-input-keymap-setup-meta-m-digit-9-bound
       "`kuro--keymap-setup-meta' binds M-0 and M-9 (digit range)."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (kbd "M-9"))
      (kuro-input-keymap-setup-meta-esc-letter-fallback-bound
       "`kuro--keymap-setup-meta' installs the raw [\\e ?a] two-key fallback."
       (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta km)
       (vector ?\e ?a)))
    "Table-driven `lookup-key' assertions that only require a live binding."))

(eval-and-compile
  (defconst kuro-input-keymap-test-2--send-byte-cases
    '((kuro-input-keymap-setup-ctrl-c-a-sends-byte-1
       "`kuro--keymap-setup-ctrl' binds C-a so it sends byte 1 via `kuro--send-ctrl'."
       "C-a"
       1)
      (kuro-input-keymap-setup-ctrl-c-z-sends-byte-26
       "`kuro--keymap-setup-ctrl' binds C-z so it sends byte 26 via `kuro--send-ctrl'."
       "C-z"
       26)
      (kuro-input-keymap-setup-ctrl-escape-sends-byte-27
       "`kuro--keymap-setup-ctrl' binds [escape] so it sends byte 27 via `kuro--send-ctrl'."
       [escape]
       27))
    "Table-driven tests for `kuro--send-ctrl' byte emission."))

(defmacro kuro-input-keymap-test-2--deftest-lookup-eq-cases (cases)
  (let ((case-list (cond
                    ((symbolp cases) (symbol-value cases))
                    ((and (consp cases) (eq (car cases) 'quote)) (cadr cases))
                    (t cases))))
    `(progn
       ,@(mapcar
          (lambda (case)
            (pcase-let ((`(,name ,doc ,setup ,event ,expected) case))
              `(ert-deftest ,name ()
                 ,doc
                 (let ((km ,setup))
                   (should (eq (lookup-key km ,event) ,expected))))))
          case-list))))

(defmacro kuro-input-keymap-test-2--deftest-lookup-live-cases (cases)
  (let ((case-list (cond
                    ((symbolp cases) (symbol-value cases))
                    ((and (consp cases) (eq (car cases) 'quote)) (cadr cases))
                    (t cases))))
    `(progn
       ,@(mapcar
          (lambda (case)
            (pcase-let ((`(,name ,doc ,setup ,event) case))
              `(ert-deftest ,name ()
                 ,doc
                 (let ((km ,setup))
                   (should (lookup-key km ,event))))))
          case-list))))

(defmacro kuro-input-keymap-test-2--deftest-send-byte-cases (cases)
  (let ((case-list (cond
                    ((symbolp cases) (symbol-value cases))
                    ((and (consp cases) (eq (car cases) 'quote)) (cadr cases))
                    (t cases))))
    `(progn
       ,@(mapcar
          (lambda (case)
            (pcase-let ((`(,name ,doc ,event ,byte) case))
              `(ert-deftest ,name ()
                 ,doc
                 (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-ctrl
                   (let ((sent nil)
                         (binding (lookup-key km (if (stringp ,event) (kbd ,event) ,event))))
                     (should (functionp binding))
                     (cl-letf (((symbol-function 'kuro--send-ctrl)
                                (lambda (value) (push value sent))))
                       (funcall binding)
                       (should (equal sent (list ,byte)))))))))
          case-list))))

(kuro-input-keymap-test-2--deftest-lookup-eq-cases kuro-input-keymap-test-2--lookup-eq-cases)

(kuro-input-keymap-test-2--deftest-lookup-live-cases kuro-input-keymap-test-2--lookup-live-cases)

(kuro-input-keymap-test-2--deftest-send-byte-cases kuro-input-keymap-test-2--send-byte-cases)

;;; Group 15: navigation — scrollback viewport, insert/delete keys

(ert-deftest kuro-input-keymap-nav-all-entries-have-live-binding ()
  "Every entry in kuro--nav-key-bindings corresponds to a live keymap binding."
  (kuro-input-keymap-test--with-built-map map
    (pcase-dolist (`(,key . ,_cmd) kuro--nav-key-bindings)
      (should (lookup-key map key)))))

(ert-deftest kuro-input-keymap-modifier-arrow-all-12-bound ()
  "All 12 modifier+arrow combinations (3 mods x 4 dirs) are bound in the keymap."
  (kuro-input-keymap-test--with-built-map map
    (dolist (mod kuro--xterm-modifier-codes)
      (dolist (arrow kuro--xterm-arrow-codes)
        (let ((event (intern (format "%s-%s" (car mod) (car arrow)))))
          (should (lookup-key map (vector event))))))))


;;; Group 16: Setup functions in isolation — fresh keymap per function

;; Each test creates a bare sparse keymap, calls one setup function, and
;; asserts that the expected keys are bound.  This exercises the six
;; kuro--keymap-setup-* functions directly rather than through
;; kuro--build-keymap, ensuring each function is independently correct.

;; --- kuro--keymap-setup-special ---

(ert-deftest kuro-input-keymap-setup-special-does-not-bind-escape ()
  "`kuro--keymap-setup-special' does not bind [escape] (that belongs to ctrl setup)."
  (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-special
    (should-not (lookup-key km [escape]))))

;; --- kuro--keymap-setup-ctrl ---

(ert-deftest kuro-input-keymap-setup-ctrl-all-table-entries-bound ()
  "`kuro--keymap-setup-ctrl' installs a live binding for every entry in `kuro--ctrl-key-table'."
  (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-ctrl
    (kuro-input-keymap-test--each-entry
     kuro--ctrl-key-table
     (lambda (entry)
       (should (lookup-key km (kbd (car entry))))))))

(ert-deftest kuro-input-keymap-setup-ctrl-fresh-map-not-polluted ()
  "`kuro--keymap-setup-ctrl' does not install any special-key binding ([return], [tab], [backspace])."
  (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-ctrl
    (should-not (lookup-key km [return]))
    (should-not (lookup-key km [tab]))
    (should-not (lookup-key km [backspace]))))

;; --- kuro--keymap-setup-meta ---

(ert-deftest kuro-input-keymap-setup-meta-punct-all-entries-bound ()
  "`kuro--keymap-setup-meta' installs a live binding for every entry in `kuro--meta-punct-bindings'."
  (kuro-input-keymap-test--with-fresh-keymap km kuro--keymap-setup-meta
    (kuro-input-keymap-test--each-entry
     kuro--meta-punct-bindings
     (lambda (entry)
       (should (lookup-key km (kbd (car entry))))))))


(provide 'kuro-input-keymap-test-2)
;;; kuro-input-keymap-test-2.el ends here
