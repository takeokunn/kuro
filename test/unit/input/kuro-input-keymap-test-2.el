;;; kuro-input-keymap-test-2.el --- Tests for kuro-input-keymap.el (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

;; kuro-input-keymap.el before loading so the file loads without the module.
(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))
(unless (fboundp 'kuro--mouse-mode-query)
  (defalias 'kuro--mouse-mode-query (lambda () 0)))
;; kuro-input-keymap.el declare-function stubs (needed if kuro-input is absent)
(dolist (sym '(kuro--self-insert kuro--RET kuro--TAB kuro--DEL
               kuro--arrow-up kuro--arrow-down kuro--arrow-left kuro--arrow-right
               kuro--HOME kuro--END kuro--INSERT kuro--DELETE
               kuro--PAGE-UP kuro--PAGE-DOWN
               kuro-scroll-up kuro-scroll-down kuro-scroll-bottom
               kuro--F1 kuro--F2 kuro--F3 kuro--F4 kuro--F5 kuro--F6
               kuro--F7 kuro--F8 kuro--F9 kuro--F10 kuro--F11 kuro--F12
               kuro--send-ctrl kuro--send-meta))
  (unless (fboundp sym)
    (defalias sym (lambda (&rest _) nil))))
(unless (fboundp 'kuro--yank)
  (defalias 'kuro--yank (lambda () nil)))
(unless (fboundp 'kuro--yank-pop)
  (defalias 'kuro--yank-pop (lambda (&optional _n) nil)))

(require 'kuro-input-keymap)

(require 'kuro-input-keymap)

;;; Group 15: navigation — scrollback viewport, insert/delete keys

(ert-deftest kuro-input-keymap-s-prior-bound-to-scroll-up ()
  "[S-prior] is bound to `kuro-scroll-up' in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map [S-prior]) #'kuro-scroll-up))))

(ert-deftest kuro-input-keymap-s-next-bound-to-scroll-down ()
  "[S-next] is bound to `kuro-scroll-down' in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map [S-next]) #'kuro-scroll-down))))

(ert-deftest kuro-input-keymap-s-end-bound-to-scroll-bottom ()
  "[S-end] is bound to `kuro-scroll-bottom' in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map [S-end]) #'kuro-scroll-bottom))))

(ert-deftest kuro-input-keymap-insert-key-is-bound ()
  "[insert] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [insert]))))

(ert-deftest kuro-input-keymap-delete-key-is-bound ()
  "[delete] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [delete]))))

(ert-deftest kuro-input-keymap-nav-all-entries-have-live-binding ()
  "Every entry in kuro--nav-key-bindings corresponds to a live keymap binding."
  (let ((map (kuro-keymap-test--built-map)))
    (pcase-dolist (`(,key . ,_cmd) kuro--nav-key-bindings)
      (should (lookup-key map key)))))

(ert-deftest kuro-input-keymap-modifier-arrow-all-12-bound ()
  "All 12 modifier+arrow combinations (3 mods x 4 dirs) are bound in the keymap."
  (let ((map (kuro-keymap-test--built-map)))
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

(ert-deftest kuro-input-keymap-setup-special-return-bound ()
  "`kuro--keymap-setup-special' binds [return] to `kuro--RET'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-special km)
    (should (eq (lookup-key km [return]) #'kuro--RET))))

(ert-deftest kuro-input-keymap-setup-special-c-m-bound ()
  "`kuro--keymap-setup-special' binds C-m to `kuro--RET'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-special km)
    (should (eq (lookup-key km (kbd "C-m")) #'kuro--RET))))

(ert-deftest kuro-input-keymap-setup-special-tab-bound ()
  "`kuro--keymap-setup-special' binds [tab] to `kuro--TAB'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-special km)
    (should (eq (lookup-key km [tab]) #'kuro--TAB))))

(ert-deftest kuro-input-keymap-setup-special-c-i-bound ()
  "`kuro--keymap-setup-special' binds C-i to `kuro--TAB'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-special km)
    (should (eq (lookup-key km (kbd "C-i")) #'kuro--TAB))))

(ert-deftest kuro-input-keymap-setup-special-backspace-bound ()
  "`kuro--keymap-setup-special' binds [backspace] to `kuro--DEL'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-special km)
    (should (eq (lookup-key km [backspace]) #'kuro--DEL))))

(ert-deftest kuro-input-keymap-setup-special-c-h-bound ()
  "`kuro--keymap-setup-special' binds C-h to `kuro--DEL'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-special km)
    (should (eq (lookup-key km (kbd "C-h")) #'kuro--DEL))))

(ert-deftest kuro-input-keymap-setup-special-del-bound ()
  "`kuro--keymap-setup-special' binds DEL to `kuro--DEL'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-special km)
    (should (eq (lookup-key km (kbd "DEL")) #'kuro--DEL))))

(ert-deftest kuro-input-keymap-setup-special-does-not-bind-escape ()
  "`kuro--keymap-setup-special' does not bind [escape] (that belongs to ctrl setup)."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-special km)
    (should-not (lookup-key km [escape]))))

;; --- kuro--keymap-setup-ctrl ---

(ert-deftest kuro-input-keymap-setup-ctrl-c-a-sends-byte-1 ()
  "`kuro--keymap-setup-ctrl' binds C-a so it sends byte 1 via `kuro--send-ctrl'."
  (let* ((km (make-sparse-keymap))
         (sent nil))
    (kuro--keymap-setup-ctrl km)
    (let ((binding (lookup-key km (kbd "C-a"))))
      (should (functionp binding))
      (cl-letf (((symbol-function 'kuro--send-ctrl)
                 (lambda (byte) (push byte sent))))
        (funcall binding)
        (should (equal sent '(1)))))))

(ert-deftest kuro-input-keymap-setup-ctrl-c-z-sends-byte-26 ()
  "`kuro--keymap-setup-ctrl' binds C-z so it sends byte 26 via `kuro--send-ctrl'."
  (let* ((km (make-sparse-keymap))
         (sent nil))
    (kuro--keymap-setup-ctrl km)
    (let ((binding (lookup-key km (kbd "C-z"))))
      (should (functionp binding))
      (cl-letf (((symbol-function 'kuro--send-ctrl)
                 (lambda (byte) (push byte sent))))
        (funcall binding)
        (should (equal sent '(26)))))))

(ert-deftest kuro-input-keymap-setup-ctrl-escape-sends-byte-27 ()
  "`kuro--keymap-setup-ctrl' binds [escape] so it sends byte 27 via `kuro--send-ctrl'."
  (let* ((km (make-sparse-keymap))
         (sent nil))
    (kuro--keymap-setup-ctrl km)
    (let ((binding (lookup-key km [escape])))
      (should (functionp binding))
      (cl-letf (((symbol-function 'kuro--send-ctrl)
                 (lambda (byte) (push byte sent))))
        (funcall binding)
        (should (equal sent '(27)))))))

(ert-deftest kuro-input-keymap-setup-ctrl-c-v-bound-to-scroll-aware ()
  "`kuro--keymap-setup-ctrl' binds C-v to `kuro--scroll-aware-ctrl-v'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-ctrl km)
    (should (eq (lookup-key km (kbd "C-v")) #'kuro--scroll-aware-ctrl-v))))

(ert-deftest kuro-input-keymap-setup-ctrl-all-table-entries-bound ()
  "`kuro--keymap-setup-ctrl' installs a live binding for every entry in `kuro--ctrl-key-table'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-ctrl km)
    (dolist (entry kuro--ctrl-key-table)
      (should (lookup-key km (kbd (car entry)))))))

(ert-deftest kuro-input-keymap-setup-ctrl-fresh-map-not-polluted ()
  "`kuro--keymap-setup-ctrl' does not install any special-key binding ([return], [tab], [backspace])."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-ctrl km)
    (should-not (lookup-key km [return]))
    (should-not (lookup-key km [tab]))
    (should-not (lookup-key km [backspace]))))

;; --- kuro--keymap-setup-meta ---

(ert-deftest kuro-input-keymap-setup-meta-m-a-bound ()
  "`kuro--keymap-setup-meta' binds M-a."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (kbd "M-a")))))

(ert-deftest kuro-input-keymap-setup-meta-m-z-bound ()
  "`kuro--keymap-setup-meta' binds M-z."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (kbd "M-z")))))

(ert-deftest kuro-input-keymap-setup-meta-m-uppercase-bound ()
  "`kuro--keymap-setup-meta' binds M-A and M-Z (uppercase range)."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (kbd "M-A")))
    (should (lookup-key km (kbd "M-Z")))))

(ert-deftest kuro-input-keymap-setup-meta-m-digit-bound ()
  "`kuro--keymap-setup-meta' binds M-0 and M-9 (digit range)."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (kbd "M-0")))
    (should (lookup-key km (kbd "M-9")))))

(ert-deftest kuro-input-keymap-setup-meta-esc-letter-fallback-bound ()
  "`kuro--keymap-setup-meta' installs the raw [\\e ?a] two-key fallback."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (vector ?\e ?a)))))

(ert-deftest kuro-input-keymap-setup-meta-m-v-bound-to-scroll-aware ()
  "`kuro--keymap-setup-meta' binds M-v to `kuro--scroll-aware-meta-v'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (eq (lookup-key km (kbd "M-v")) #'kuro--scroll-aware-meta-v))))

(ert-deftest kuro-input-keymap-setup-meta-esc-v-fallback-bound-to-scroll-aware ()
  "`kuro--keymap-setup-meta' binds [\\e ?v] two-key fallback to `kuro--scroll-aware-meta-v'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (eq (lookup-key km (vector ?\e ?v)) #'kuro--scroll-aware-meta-v))))

(ert-deftest kuro-input-keymap-setup-meta-m-del-bound-to-meta-backspace ()
  "`kuro--keymap-setup-meta' binds M-DEL to `kuro--send-meta-backspace'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (eq (lookup-key km (kbd "M-DEL")) #'kuro--send-meta-backspace))))

(ert-deftest kuro-input-keymap-setup-meta-m-backspace-bound-to-meta-backspace ()
  "`kuro--keymap-setup-meta' binds M-<backspace> to `kuro--send-meta-backspace'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (should (eq (lookup-key km (kbd "M-<backspace>")) #'kuro--send-meta-backspace))))

(ert-deftest kuro-input-keymap-setup-meta-punct-all-entries-bound ()
  "`kuro--keymap-setup-meta' installs a live binding for every entry in `kuro--meta-punct-bindings'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-meta km)
    (dolist (entry kuro--meta-punct-bindings)
      (should (lookup-key km (kbd (car entry)))))))

(ert-deftest kuro-input-keymap-setup-meta-m-b-sends-char-b ()
  "`kuro--keymap-setup-meta' wires M-b so it sends ?b via `kuro--send-meta'."
  (let* ((km (make-sparse-keymap))
         (sent nil))
    (kuro--keymap-setup-meta km)
    (let ((binding (lookup-key km (kbd "M-b"))))
      (should (functionp binding))
      (cl-letf (((symbol-function 'kuro--send-meta)
                 (lambda (c) (push c sent))))
        (funcall binding)
        (should (equal sent (list ?b)))))))


(provide 'kuro-input-keymap-test-2)
;;; kuro-input-keymap-test-2.el ends here
