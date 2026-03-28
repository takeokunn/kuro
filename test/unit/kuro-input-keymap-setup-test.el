;;; kuro-input-keymap-ext-test.el --- Extended tests for kuro-input-keymap.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; ERT tests for kuro-input-keymap.el — setup function isolation (Group 16).
;; These tests exercise the six kuro--keymap-setup-* functions directly
;; rather than through kuro--build-keymap, ensuring each function is
;; independently correct.
;;
;; Pure Elisp tests — no Rust dynamic module required.
;; All FFI dependencies are stubbed before requiring the module.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub FFI and input function symbols consumed transitively by
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


;;; Helper

(defun kuro-keymap-test--built-map ()
  "Return a freshly built Kuro keymap with no exceptions.
Saves and restores `kuro--keymap' so global state is not corrupted."
  (let ((kuro-keymap-exceptions nil)
        (orig kuro--keymap))
    (unwind-protect
        (kuro--build-keymap)
      (setq kuro--keymap orig))))


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

;; --- kuro--keymap-setup-navigation ---

(ert-deftest kuro-input-keymap-setup-navigation-arrow-keys-bound ()
  "`kuro--keymap-setup-navigation' binds all four arrow keys."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-navigation km)
    (should (lookup-key km [up]))
    (should (lookup-key km [down]))
    (should (lookup-key km [left]))
    (should (lookup-key km [right]))))

(ert-deftest kuro-input-keymap-setup-navigation-home-end-bound ()
  "`kuro--keymap-setup-navigation' binds [home] and [end]."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-navigation km)
    (should (eq (lookup-key km [home]) #'kuro--HOME))
    (should (eq (lookup-key km [end])  #'kuro--END))))

(ert-deftest kuro-input-keymap-setup-navigation-page-keys-bound ()
  "`kuro--keymap-setup-navigation' binds [prior] and [next]."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-navigation km)
    (should (eq (lookup-key km [prior]) #'kuro--PAGE-UP))
    (should (eq (lookup-key km [next])  #'kuro--PAGE-DOWN))))

(ert-deftest kuro-input-keymap-setup-navigation-insert-delete-bound ()
  "`kuro--keymap-setup-navigation' binds [insert] and [delete]."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-navigation km)
    (should (eq (lookup-key km [insert]) #'kuro--INSERT))
    (should (eq (lookup-key km [delete]) #'kuro--DELETE))))

(ert-deftest kuro-input-keymap-setup-navigation-scrollback-keys-bound ()
  "`kuro--keymap-setup-navigation' binds [S-prior], [S-next], [S-end]."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-navigation km)
    (should (eq (lookup-key km [S-prior]) #'kuro-scroll-up))
    (should (eq (lookup-key km [S-next])  #'kuro-scroll-down))
    (should (eq (lookup-key km [S-end])   #'kuro-scroll-bottom))))

(ert-deftest kuro-input-keymap-setup-navigation-fkeys-all-bound ()
  "`kuro--keymap-setup-navigation' binds all 12 function keys."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-navigation km)
    (dolist (fkey '([f1] [f2] [f3] [f4] [f5] [f6]
                    [f7] [f8] [f9] [f10] [f11] [f12]))
      (should (lookup-key km fkey)))))

(ert-deftest kuro-input-keymap-setup-navigation-modifier-arrows-all-bound ()
  "`kuro--keymap-setup-navigation' binds all 12 modifier+arrow combinations."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-navigation km)
    (dolist (mod kuro--xterm-modifier-codes)
      (dolist (arrow kuro--xterm-arrow-codes)
        (let ((event (intern (format "%s-%s" (car mod) (car arrow)))))
          (should (lookup-key km (vector event))))))))

(ert-deftest kuro-input-keymap-setup-navigation-all-nav-table-entries-bound ()
  "`kuro--keymap-setup-navigation' installs a live binding for every entry in `kuro--nav-key-bindings'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-navigation km)
    (pcase-dolist (`(,key . ,_cmd) kuro--nav-key-bindings)
      (should (lookup-key km key)))))

;; --- kuro--keymap-setup-mouse ---

(ert-deftest kuro-input-keymap-setup-mouse-down-mouse-1-bound ()
  "`kuro--keymap-setup-mouse' binds [down-mouse-1] to `kuro--mouse-press'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-mouse km)
    (should (eq (lookup-key km [down-mouse-1]) #'kuro--mouse-press))))

(ert-deftest kuro-input-keymap-setup-mouse-mouse-1-bound ()
  "`kuro--keymap-setup-mouse' binds [mouse-1] to `kuro--mouse-release'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-mouse km)
    (should (eq (lookup-key km [mouse-1]) #'kuro--mouse-release))))

(ert-deftest kuro-input-keymap-setup-mouse-mouse-4-scroll-up-bound ()
  "`kuro--keymap-setup-mouse' binds [mouse-4] to `kuro--mouse-scroll-up'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-mouse km)
    (should (eq (lookup-key km [mouse-4]) #'kuro--mouse-scroll-up))))

(ert-deftest kuro-input-keymap-setup-mouse-mouse-5-scroll-down-bound ()
  "`kuro--keymap-setup-mouse' binds [mouse-5] to `kuro--mouse-scroll-down'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-mouse km)
    (should (eq (lookup-key km [mouse-5]) #'kuro--mouse-scroll-down))))

(ert-deftest kuro-input-keymap-setup-mouse-all-three-buttons-press-bound ()
  "`kuro--keymap-setup-mouse' binds [down-mouse-2] and [down-mouse-3] to `kuro--mouse-press'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-mouse km)
    (should (eq (lookup-key km [down-mouse-2]) #'kuro--mouse-press))
    (should (eq (lookup-key km [down-mouse-3]) #'kuro--mouse-press))))

(ert-deftest kuro-input-keymap-setup-mouse-all-three-buttons-release-bound ()
  "`kuro--keymap-setup-mouse' binds [mouse-2] and [mouse-3] to `kuro--mouse-release'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-mouse km)
    (should (eq (lookup-key km [mouse-2]) #'kuro--mouse-release))
    (should (eq (lookup-key km [mouse-3]) #'kuro--mouse-release))))

(ert-deftest kuro-input-keymap-setup-mouse-all-table-entries-bound ()
  "`kuro--keymap-setup-mouse' installs a live binding for every entry in `kuro--mouse-bindings'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-mouse km)
    (pcase-dolist (`(,key . ,_cmd) kuro--mouse-bindings)
      (should (lookup-key km key)))))

;; --- kuro--keymap-setup-yank ---

(ert-deftest kuro-input-keymap-setup-yank-remap-yank-bound ()
  "`kuro--keymap-setup-yank' remaps `yank' to `kuro--yank'."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions nil))
    (kuro--keymap-setup-yank km)
    (should (eq (lookup-key km [remap yank]) #'kuro--yank))))

(ert-deftest kuro-input-keymap-setup-yank-remap-yank-pop-bound ()
  "`kuro--keymap-setup-yank' remaps `yank-pop' to `kuro--yank-pop'."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions nil))
    (kuro--keymap-setup-yank km)
    (should (eq (lookup-key km [remap yank-pop]) #'kuro--yank-pop))))

(ert-deftest kuro-input-keymap-setup-yank-remap-clipboard-yank-bound ()
  "`kuro--keymap-setup-yank' remaps `clipboard-yank' to `kuro--yank'."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions nil))
    (kuro--keymap-setup-yank km)
    (should (eq (lookup-key km [remap clipboard-yank]) #'kuro--yank))))

(ert-deftest kuro-input-keymap-setup-yank-exception-clears-binding ()
  "`kuro--keymap-setup-yank' clears a binding listed in `kuro-keymap-exceptions'."
  ;; First install meta bindings so M-x is present, then yank-setup should
  ;; clear it when it appears in exceptions.
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions '("M-x")))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (kbd "M-x")))   ; confirm it is installed
    (kuro--keymap-setup-yank km)
    (should-not (lookup-key km (kbd "M-x")))))

(ert-deftest kuro-input-keymap-setup-yank-exception-clears-esc-fallback ()
  "`kuro--keymap-setup-yank' clears the ESC+char fallback for an M-CHAR exception."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions '("M-b")))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (vector ?\e ?b)))  ; confirm installed
    (kuro--keymap-setup-yank km)
    (should-not (lookup-key km (vector ?\e ?b)))))

(ert-deftest kuro-input-keymap-setup-yank-no-exceptions-keeps-yank-remap ()
  "With an empty exceptions list, all three yank remaps remain after `kuro--keymap-setup-yank'."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions nil))
    (kuro--keymap-setup-yank km)
    (should (lookup-key km [remap yank]))
    (should (lookup-key km [remap yank-pop]))
    (should (lookup-key km [remap clipboard-yank]))))


(provide 'kuro-input-keymap-ext-test)
;;; kuro-input-keymap-ext-test.el ends here
