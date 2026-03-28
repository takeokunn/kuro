;;; kuro-input-keymap-ext2-test.el --- Extended tests for kuro-input-keymap.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Extended ERT tests for kuro-input-keymap.el keymap construction and table
;; contents (Groups 8-15).
;; These tests exercise:
;;   - kuro--nav-key-bindings and kuro--mouse-bindings tables (Group 8)
;;   - kuro--fkey-handlers table (Group 9)
;;   - kuro--keymap-setup-special — C-m, C-i, C-h, DEL aliases (Group 10)
;;   - kuro-keymap-exceptions — exception removal clears binding (Group 11)
;;   - kuro--send-meta-backspace behavior (Group 12)
;;   - ctrl setup — escape sends byte 27; selected ctrl bytes (Group 13)
;;   - meta loop — M-digit and ESC+letter two-key fallbacks (Group 14)
;;   - navigation — scrollback viewport, insert/delete keys (Group 15)
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


(defun kuro-keymap-test--built-map ()
  "Return a freshly built Kuro keymap with no exceptions.
Saves and restores `kuro--keymap' so global state is not corrupted."
  (let ((kuro-keymap-exceptions nil)
        (orig kuro--keymap))
    (unwind-protect
        (kuro--build-keymap)
      (setq kuro--keymap orig))))


;;; Group 8: kuro--nav-key-bindings and kuro--mouse-bindings tables

(ert-deftest kuro-input-keymap-nav-bindings-has-13-entries ()
  "kuro--nav-key-bindings contains exactly 13 entries."
  (should (= (length kuro--nav-key-bindings) 13)))

(ert-deftest kuro-input-keymap-nav-bindings-entries-are-cons-pairs ()
  "Every entry in kuro--nav-key-bindings is a (VECTOR . SYMBOL) cons pair."
  (dolist (entry kuro--nav-key-bindings)
    (should (consp entry))
    (should (vectorp (car entry)))
    (should (symbolp (cdr entry)))))

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
  (dolist (entry kuro--mouse-bindings)
    (should (consp entry))
    (should (vectorp (car entry)))
    (should (symbolp (cdr entry)))))

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
    (dolist (fkey '([f1] [f2] [f3] [f4] [f5] [f6]
                    [f7] [f8] [f9] [f10] [f11] [f12]))
      (should (lookup-key map fkey)))))

(ert-deftest kuro-input-keymap-build-has-meta-punct-bindings ()
  "M-. M-< M-> M-? M-/ M-_ are all bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (dolist (key (mapcar (lambda (e) (kbd (car e))) kuro--meta-punct-bindings))
      (should (lookup-key map key)))))


;;; Group 9: kuro--fkey-handlers table

(ert-deftest kuro-input-keymap-fkey-handlers-has-12-entries ()
  "kuro--fkey-handlers contains exactly 12 entries (F1-F12)."
  (should (= (length kuro--fkey-handlers) 12)))

(ert-deftest kuro-input-keymap-fkey-handlers-entries-are-cons-pairs ()
  "Every entry in kuro--fkey-handlers is a (SYMBOL . SYMBOL) cons pair."
  (dolist (entry kuro--fkey-handlers)
    (should (consp entry))
    (should (symbolp (car entry)))
    (should (symbolp (cdr entry)))))

(ert-deftest kuro-input-keymap-fkey-handlers-spot-check-f1 ()
  "f1 maps to kuro--F1 in kuro--fkey-handlers."
  (should (eq (cdr (assq 'f1 kuro--fkey-handlers)) 'kuro--F1)))

(ert-deftest kuro-input-keymap-fkey-handlers-spot-check-f12 ()
  "f12 maps to kuro--F12 in kuro--fkey-handlers."
  (should (eq (cdr (assq 'f12 kuro--fkey-handlers)) 'kuro--F12)))

(ert-deftest kuro-input-keymap-fkey-handlers-all-keys-are-fN ()
  "All key symbols in kuro--fkey-handlers match the pattern fN (f1-f12)."
  (dolist (entry kuro--fkey-handlers)
    (should (string-match-p "\\`f[0-9]+\\'" (symbol-name (car entry))))))


;;; Group 10: kuro--keymap-setup-special — C-m, C-i, C-h, DEL aliases

(ert-deftest kuro-input-keymap-build-c-m-is-ret ()
  "C-m is bound to kuro--RET (same as [return]) in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "C-m")) #'kuro--RET))))

(ert-deftest kuro-input-keymap-build-c-i-is-tab ()
  "C-i is bound to kuro--TAB (same as [tab]) in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "C-i")) #'kuro--TAB))))

(ert-deftest kuro-input-keymap-build-c-h-is-del ()
  "C-h is bound to kuro--DEL (same as [backspace]) in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "C-h")) #'kuro--DEL))))

(ert-deftest kuro-input-keymap-build-del-is-del ()
  "DEL (kbd \"DEL\") is bound to kuro--DEL in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "DEL")) #'kuro--DEL))))


;;; Group 11: kuro-keymap-exceptions — exception removal clears binding

(ert-deftest kuro-input-keymap-exception-removes-binding ()
  "A key listed in kuro-keymap-exceptions is absent from the built keymap."
  (let* ((kuro-keymap-exceptions '("M-x"))
         (orig kuro--keymap)
         (map (unwind-protect
                  (kuro--build-keymap)
                (setq kuro--keymap orig))))
    ;; The binding for M-x must be nil (removed)
    (should-not (lookup-key map (kbd "M-x")))))

(ert-deftest kuro-input-keymap-exception-also-clears-esc-prefix-fallback ()
  "A M-CHAR exception also clears the ESC+char two-key fallback vector binding."
  (let* ((kuro-keymap-exceptions '("M-b"))
         (orig kuro--keymap)
         (map (unwind-protect
                  (kuro--build-keymap)
                (setq kuro--keymap orig))))
    ;; The raw [\e ?b] two-key form must also be cleared
    (should-not (lookup-key map (vector ?\e ?b)))))


;;; Group 12: kuro--send-meta-backspace behavior

(ert-deftest kuro-input-keymap-send-meta-backspace-sends-esc-del ()
  "`kuro--send-meta-backspace' sends ESC+DEL (\\e\\x7f) via kuro--send-key."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      (kuro--send-meta-backspace)
      (should (equal (car sent) (string ?\e ?\x7f))))))

(ert-deftest kuro-input-keymap-send-meta-backspace-schedules-render ()
  "`kuro--send-meta-backspace' calls `kuro--schedule-immediate-render'."
  (let ((render-called nil))
    (cl-letf (((symbol-function 'kuro--send-key) (lambda (_) nil))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () (setq render-called t))))
      (kuro--send-meta-backspace)
      (should render-called))))

(ert-deftest kuro-input-keymap-build-m-del-bound-to-meta-backspace ()
  "M-DEL is bound to `kuro--send-meta-backspace' in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "M-DEL")) #'kuro--send-meta-backspace))))

(ert-deftest kuro-input-keymap-build-m-backspace-bound-to-meta-backspace ()
  "M-<backspace> is bound to `kuro--send-meta-backspace' in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "M-<backspace>")) #'kuro--send-meta-backspace))))


;;; Group 13: ctrl setup — escape sends byte 27; selected ctrl bytes

(ert-deftest kuro-input-keymap-escape-sends-ctrl-27 ()
  "[escape] binding sends byte 27 (ESC) via kuro--send-ctrl."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map [escape]))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-ctrl)
               (lambda (byte) (push byte sent))))
      (funcall binding)
      (should (equal sent '(27))))))

(ert-deftest kuro-input-keymap-c-a-sends-ctrl-1 ()
  "C-a binding sends byte 1 via kuro--send-ctrl."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map (kbd "C-a")))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-ctrl)
               (lambda (byte) (push byte sent))))
      (funcall binding)
      (should (equal sent '(1))))))

(ert-deftest kuro-input-keymap-c-z-sends-ctrl-26 ()
  "C-z binding sends byte 26 via kuro--send-ctrl."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map (kbd "C-z")))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-ctrl)
               (lambda (byte) (push byte sent))))
      (funcall binding)
      (should (equal sent '(26))))))

(ert-deftest kuro-input-keymap-ctrl-all-entries-have-live-binding ()
  "Every entry in kuro--ctrl-key-table corresponds to a live keymap binding."
  (let ((map (kuro-keymap-test--built-map)))
    (dolist (entry kuro--ctrl-key-table)
      (should (lookup-key map (kbd (car entry)))))))


;;; Group 14: meta loop — M-digit and ESC+letter two-key fallbacks

(ert-deftest kuro-input-keymap-m-0-is-bound ()
  "M-0 is bound in the built keymap (digit range)."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map (kbd "M-0")))))

(ert-deftest kuro-input-keymap-m-9-is-bound ()
  "M-9 is bound in the built keymap (digit range)."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map (kbd "M-9")))))

(ert-deftest kuro-input-keymap-m-digits-send-correct-char ()
  "M-5 sends character ?5 via kuro--send-meta."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map (kbd "M-5")))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-meta)
               (lambda (c) (push c sent))))
      (funcall binding)
      (should (equal sent (list ?5))))))

(ert-deftest kuro-input-keymap-esc-letter-two-key-fallback-is-bound ()
  "The raw [\\e ?a] two-key fallback is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map (vector ?\e ?a)))))

(ert-deftest kuro-input-keymap-esc-letter-two-key-sends-correct-char ()
  "The [\\e ?b] binding sends ?b via kuro--send-meta."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map (vector ?\e ?b)))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-meta)
               (lambda (c) (push c sent))))
      (funcall binding)
      (should (equal sent (list ?b))))))

(ert-deftest kuro-input-keymap-esc-uppercase-letter-two-key-is-bound ()
  "The raw [\\e ?Z] two-key fallback is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map (vector ?\e ?Z)))))


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


(provide 'kuro-input-keymap-ext2-test)
;;; kuro-input-keymap-ext2-test.el ends here
