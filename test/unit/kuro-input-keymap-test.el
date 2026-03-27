;;; kuro-input-keymap-test.el --- Tests for kuro-input-keymap.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; ERT tests for kuro-input-keymap.el keymap construction and table contents.
;; These tests exercise:
;;   - kuro--ctrl-key-table structure and spot-check values
;;   - kuro--xterm-modifier-codes table structure
;;   - kuro--xterm-arrow-codes table structure
;;   - kuro--build-keymap result (keymapp, special/ctrl/meta/nav bindings)
;;   - kuro--send-meta-backspace sequence
;;   - Modifier+arrow xterm CSI sequences produced by the keymap
;;   - yank / yank-pop / clipboard-yank remap assertions (Group 6)
;;
;; Pure Elisp tests — no Rust dynamic module required.
;; All FFI dependencies are stubbed before requiring the module.
;;
;; NOTE: kuro-input-test.el already covers individual Ctrl+letter and
;; Meta+letter binding checks exhaustively.  This file focuses on the
;; structural properties of the tables and the keymap builder itself
;; to avoid duplication.

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


;;; Group 1: kuro--ctrl-key-table structure

(ert-deftest kuro-input-keymap-ctrl-table-has-24-entries ()
  "kuro--ctrl-key-table contains exactly 24 entries.
C-c is intentionally absent (reserved as prefix key)."
  (should (= (length kuro--ctrl-key-table) 24)))

(ert-deftest kuro-input-keymap-ctrl-table-entries-are-cons-pairs ()
  "Every entry in kuro--ctrl-key-table is a (STRING . INTEGER) cons pair."
  (dolist (entry kuro--ctrl-key-table)
    (should (consp entry))
    (should (stringp (car entry)))
    (should (integerp (cdr entry)))))

(ert-deftest kuro-input-keymap-ctrl-table-bytes-in-range ()
  "Every control byte in kuro--ctrl-key-table is in the range 1–31 (ASCII ctrl range)."
  (dolist (entry kuro--ctrl-key-table)
    (let ((byte (cdr entry)))
      (should (>= byte 1))
      (should (<= byte 31)))))

(ert-deftest kuro-input-keymap-ctrl-table-no-c-c ()
  "kuro--ctrl-key-table does not contain C-c (byte 3, the prefix key)."
  (should-not (assoc "C-c" kuro--ctrl-key-table))
  (should-not (rassq 3 kuro--ctrl-key-table)))

(ert-deftest kuro-input-keymap-ctrl-table-spot-check-c-a ()
  "C-a maps to control byte 1 in kuro--ctrl-key-table."
  (should (= (cdr (assoc "C-a" kuro--ctrl-key-table)) 1)))

(ert-deftest kuro-input-keymap-ctrl-table-spot-check-c-z ()
  "C-z maps to control byte 26 in kuro--ctrl-key-table."
  (should (= (cdr (assoc "C-z" kuro--ctrl-key-table)) 26)))

(ert-deftest kuro-input-keymap-ctrl-table-spot-check-c-backslash ()
  "C-\\ maps to control byte 28 in kuro--ctrl-key-table."
  (should (= (cdr (assoc "C-\\" kuro--ctrl-key-table)) 28)))

(ert-deftest kuro-input-keymap-ctrl-table-spot-check-c-bracket ()
  "C-] maps to control byte 29 in kuro--ctrl-key-table."
  (should (= (cdr (assoc "C-]" kuro--ctrl-key-table)) 29)))

(ert-deftest kuro-input-keymap-ctrl-table-spot-check-c-underscore ()
  "C-_ maps to control byte 31 in kuro--ctrl-key-table."
  (should (= (cdr (assoc "C-_" kuro--ctrl-key-table)) 31)))

(ert-deftest kuro-input-keymap-ctrl-table-no-duplicate-bytes ()
  "kuro--ctrl-key-table has no duplicate control-byte values."
  (let ((bytes (mapcar #'cdr kuro--ctrl-key-table)))
    (should (= (length bytes) (length (delete-dups (copy-sequence bytes)))))))


;;; Group 2: kuro--xterm-modifier-codes table

(ert-deftest kuro-input-keymap-modifier-codes-has-3-entries ()
  "kuro--xterm-modifier-codes contains exactly 3 entries: S, M, C."
  (should (= (length kuro--xterm-modifier-codes) 3)))

(ert-deftest kuro-input-keymap-modifier-codes-shift-is-2 ()
  "Shift modifier code is 2 in kuro--xterm-modifier-codes."
  (should (= (cdr (assq 'S kuro--xterm-modifier-codes)) 2)))

(ert-deftest kuro-input-keymap-modifier-codes-meta-is-3 ()
  "Meta/Alt modifier code is 3 in kuro--xterm-modifier-codes."
  (should (= (cdr (assq 'M kuro--xterm-modifier-codes)) 3)))

(ert-deftest kuro-input-keymap-modifier-codes-ctrl-is-5 ()
  "Ctrl modifier code is 5 in kuro--xterm-modifier-codes."
  (should (= (cdr (assq 'C kuro--xterm-modifier-codes)) 5)))


;;; Group 3: kuro--xterm-arrow-codes table

(ert-deftest kuro-input-keymap-arrow-codes-has-4-entries ()
  "kuro--xterm-arrow-codes contains exactly 4 entries: up, down, right, left."
  (should (= (length kuro--xterm-arrow-codes) 4)))

(ert-deftest kuro-input-keymap-arrow-codes-spot-check ()
  "Arrow code final bytes are A=up, B=down, C=right, D=left (VT100 CUU/CUD/CUF/CUB)."
  (should (= (cdr (assq 'up    kuro--xterm-arrow-codes)) ?A))
  (should (= (cdr (assq 'down  kuro--xterm-arrow-codes)) ?B))
  (should (= (cdr (assq 'right kuro--xterm-arrow-codes)) ?C))
  (should (= (cdr (assq 'left  kuro--xterm-arrow-codes)) ?D)))


;;; Group 4: kuro--build-keymap result

(defun kuro-keymap-test--built-map ()
  "Return a freshly built Kuro keymap with no exceptions.
Saves and restores `kuro--keymap' so global state is not corrupted."
  (let ((kuro-keymap-exceptions nil)
        (orig kuro--keymap))
    (unwind-protect
        (kuro--build-keymap)
      (setq kuro--keymap orig))))

(ert-deftest kuro-input-keymap-build-returns-keymap ()
  "kuro--build-keymap returns a value satisfying keymapp."
  (should (keymapp (kuro-keymap-test--built-map))))

(ert-deftest kuro-input-keymap-build-stores-in-variable ()
  "kuro--build-keymap stores the result in kuro--keymap."
  (let ((orig kuro--keymap)
        (kuro-keymap-exceptions nil))
    (unwind-protect
        (progn
          (kuro--build-keymap)
          (should (keymapp kuro--keymap)))
      (setq kuro--keymap orig))))

(ert-deftest kuro-input-keymap-build-has-self-insert-remap ()
  "The built keymap remaps self-insert-command."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [remap self-insert-command]))))

(ert-deftest kuro-input-keymap-build-has-return-binding ()
  "[return] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [return]))))

(ert-deftest kuro-input-keymap-build-has-tab-binding ()
  "[tab] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [tab]))))

(ert-deftest kuro-input-keymap-build-has-backspace-binding ()
  "[backspace] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [backspace]))))

(ert-deftest kuro-input-keymap-build-has-escape-binding ()
  "[escape] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [escape]))))

(ert-deftest kuro-input-keymap-build-has-arrow-bindings ()
  "All four arrow keys are bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [up]))
    (should (lookup-key map [down]))
    (should (lookup-key map [left]))
    (should (lookup-key map [right]))))

(ert-deftest kuro-input-keymap-build-has-mouse-bindings ()
  "Mouse press, release, and scroll events are bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [down-mouse-1]))
    (should (lookup-key map [mouse-1]))
    (should (lookup-key map [mouse-4]))
    (should (lookup-key map [mouse-5]))))


;;; Group 5: Modifier+arrow xterm CSI sequences

(defmacro kuro-keymap-test--modifier-arrow-seq (mod-sym arrow-sym)
  "Return the sequence the keymap binding for MOD-SYM+ARROW-SYM would send.
Calls the binding function with kuro--send-key and
kuro--schedule-immediate-render stubbed, and captures the sent string."
  `(let* ((map (kuro-keymap-test--built-map))
          (event (intern (format "%s-%s" ',mod-sym ',arrow-sym)))
          (binding (lookup-key map (vector event)))
          (sent nil))
     (should (functionp binding))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (push s sent)))
               ((symbol-function 'kuro--schedule-immediate-render)
                (lambda () nil)))
       (funcall binding))
     (car sent)))

(ert-deftest kuro-input-keymap-shift-up-sends-csi-1-2A ()
  "S-up sends ESC[1;2A (xterm Shift+Up)."
  (should (equal (kuro-keymap-test--modifier-arrow-seq S up) "\e[1;2A")))

(ert-deftest kuro-input-keymap-ctrl-right-sends-csi-1-5C ()
  "C-right sends ESC[1;5C (xterm Ctrl+Right)."
  (should (equal (kuro-keymap-test--modifier-arrow-seq C right) "\e[1;5C")))

(ert-deftest kuro-input-keymap-meta-down-sends-csi-1-3B ()
  "M-down sends ESC[1;3B (xterm Alt+Down)."
  (should (equal (kuro-keymap-test--modifier-arrow-seq M down) "\e[1;3B")))

(ert-deftest kuro-input-keymap-ctrl-left-sends-csi-1-5D ()
  "C-left sends ESC[1;5D (xterm Ctrl+Left)."
  (should (equal (kuro-keymap-test--modifier-arrow-seq C left) "\e[1;5D")))

(ert-deftest kuro-input-keymap-shift-down-sends-csi-1-2B ()
  "S-down sends ESC[1;2B (xterm Shift+Down)."
  (should (equal (kuro-keymap-test--modifier-arrow-seq S down) "\e[1;2B")))

(ert-deftest kuro-input-keymap-meta-right-sends-csi-1-3C ()
  "M-right sends ESC[1;3C (xterm Alt+Right)."
  (should (equal (kuro-keymap-test--modifier-arrow-seq M right) "\e[1;3C")))


;;; Group 6: Yank remaps

(ert-deftest kuro-input-keymap-build-has-yank-remap ()
  "The built keymap remaps yank to kuro--yank."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map [remap yank]) #'kuro--yank))))

(ert-deftest kuro-input-keymap-build-has-yank-pop-remap ()
  "The built keymap remaps yank-pop to kuro--yank-pop."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map [remap yank-pop]) #'kuro--yank-pop))))

(ert-deftest kuro-input-keymap-build-has-clipboard-yank-remap ()
  "The built keymap remaps clipboard-yank to kuro--yank (for Cmd+V on macOS)."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map [remap clipboard-yank]) #'kuro--yank))))

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
  (dolist (entry kuro--meta-punct-bindings)
    (should (consp entry))
    (should (stringp (car entry)))
    (should (integerp (cdr entry)))))

(ert-deftest kuro-input-keymap-meta-punct-spot-check-dot ()
  "\"M-.\" maps to ?. in kuro--meta-punct-bindings."
  (should (= (cdr (assoc "M-." kuro--meta-punct-bindings)) ?.)))

(ert-deftest kuro-input-keymap-meta-punct-spot-check-slash ()
  "\"M-/\" maps to ?/ in kuro--meta-punct-bindings."
  (should (= (cdr (assoc "M-/" kuro--meta-punct-bindings)) ?/)))

(ert-deftest kuro-input-keymap-meta-punct-spot-check-underscore ()
  "\"M-_\" maps to ?_ in kuro--meta-punct-bindings."
  (should (= (cdr (assoc "M-_" kuro--meta-punct-bindings)) ?_)))

(ert-deftest kuro-input-keymap-meta-punct-no-alphanumeric ()
  "kuro--meta-punct-bindings contains no alphabetic or digit character bindings."
  (dolist (entry kuro--meta-punct-bindings)
    (let ((c (cdr entry)))
      (should-not (or (<= ?a c ?z) (<= ?A c ?Z) (<= ?0 c ?9))))))


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


(provide 'kuro-input-keymap-test)
;;; kuro-input-keymap-test.el ends here
