;;; kuro-input-keymap-test-4.el --- Tests for kuro-input-keymap.el (part 4)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keymap-test-support)

;; --- kuro--keymap-setup-navigation ---

(kuro-input-keymap-test--deftest-setup-binding-cases
 kuro-input-keymap-setup-navigation-arrow-keys-bound
 kuro-input-keymap-setup-navigation-home-end-bound
 kuro-input-keymap-setup-navigation-page-keys-bound
 kuro-input-keymap-setup-navigation-insert-delete-bound
 kuro-input-keymap-setup-navigation-scrollback-keys-bound)

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

(kuro-input-keymap-test--deftest-setup-binding-cases
 kuro-input-keymap-setup-mouse-down-mouse-1-bound
 kuro-input-keymap-setup-mouse-mouse-1-bound
 kuro-input-keymap-setup-mouse-mouse-4-scroll-up-bound
 kuro-input-keymap-setup-mouse-mouse-5-scroll-down-bound
 kuro-input-keymap-setup-mouse-all-three-buttons-press-bound
 kuro-input-keymap-setup-mouse-all-three-buttons-release-bound)

(ert-deftest kuro-input-keymap-setup-mouse-all-table-entries-bound ()
  "`kuro--keymap-setup-mouse' installs a live binding for every entry in `kuro--mouse-bindings'."
  (let ((km (make-sparse-keymap)))
    (kuro--keymap-setup-mouse km)
    (pcase-dolist (`(,key . ,_cmd) kuro--mouse-bindings)
      (should (lookup-key km key)))))

;; --- kuro--keymap-setup-yank ---

(kuro-input-keymap-test--deftest-setup-binding-cases
 kuro-input-keymap-setup-yank-remap-yank-bound
 kuro-input-keymap-setup-yank-remap-yank-pop-bound
 kuro-input-keymap-setup-yank-remap-clipboard-yank-bound)

(ert-deftest kuro-input-keymap-setup-yank-exception-clears-binding ()
  "`kuro--keymap-apply-exceptions' clears a binding listed in `kuro-keymap-exceptions'.
This behavior moved from `kuro--keymap-setup-yank' to the dedicated
`kuro--keymap-apply-exceptions' function to allow building a char-mode keymap
without exception removal."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions '("M-x")))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (kbd "M-x")))   ; confirm it is installed
    (kuro--keymap-apply-exceptions km)
    (should-not (lookup-key km (kbd "M-x")))))

(ert-deftest kuro-input-keymap-setup-yank-exception-clears-esc-fallback ()
  "`kuro--keymap-apply-exceptions' clears the ESC+char fallback for M-CHAR exceptions.
This behavior moved from `kuro--keymap-setup-yank' to `kuro--keymap-apply-exceptions'."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions '("M-b")))
    (kuro--keymap-setup-meta km)
    (should (lookup-key km (vector ?\e ?b)))  ; confirm installed
    (kuro--keymap-apply-exceptions km)
    (should-not (lookup-key km (vector ?\e ?b)))))

(ert-deftest kuro-input-keymap-setup-yank-no-exceptions-keeps-yank-remap ()
  "With an empty exceptions list, all three yank remaps remain after `kuro--keymap-setup-yank'."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions nil))
    (kuro--keymap-setup-yank km)
    (should (lookup-key km [remap yank]))
    (should (lookup-key km [remap yank-pop]))
    (should (lookup-key km [remap clipboard-yank]))))


;;; Group 17: Shift+Tab and Shift+Return KKP bindings

(kuro-input-keymap-test--deftest-shifted-key-send-cases)

(ert-deftest kuro-input-keymap--g17-kkp-arrow-codepoints-constants ()
  "KKP arrow codepoints alist has all four directions."
  (should (assq 'up    kuro--kkp-arrow-codepoints))
  (should (assq 'down  kuro--kkp-arrow-codepoints))
  (should (assq 'left  kuro--kkp-arrow-codepoints))
  (should (assq 'right kuro--kkp-arrow-codepoints)))

;;; Group 18: kuro--yank-bindings table + named shift helpers

(ert-deftest kuro-input-keymap--g18-yank-bindings-non-empty ()
  "`kuro--yank-bindings' must have at least 3 entries."
  (should (>= (length kuro--yank-bindings) 3)))

(ert-deftest kuro-input-keymap--g18-yank-bindings-all-commands-bound ()
  "Every target command in `kuro--yank-bindings' must be a bound function symbol."
  (dolist (b kuro--yank-bindings)
    (should (fboundp (cdr b)))))

(ert-deftest kuro-input-keymap--g18-yank-bindings-installs-all ()
  "`kuro--keymap-setup-yank' installs every remap from `kuro--yank-bindings'."
  (let ((map (make-sparse-keymap)))
    (kuro--keymap-setup-yank map)
    (dolist (b kuro--yank-bindings)
      (should (eq (lookup-key map (vector 'remap (car b)))
                  (cdr b))))))

(ert-deftest kuro-input-keymap--g18-backtab-and-stab-share-same-command ()
  "[backtab] and [S-tab] must both map to `kuro--send-shifted-tab'."
  (let ((map (kuro--build-keymap)))
    (should (eq (lookup-key map [backtab]) #'kuro--send-shifted-tab))
    (should (eq (lookup-key map [S-tab])   #'kuro--send-shifted-tab))))

(ert-deftest kuro-input-keymap--g18-send-shifted-tab-is-interactive ()
  "`kuro--send-shifted-tab' must be an interactive command."
  (should (commandp #'kuro--send-shifted-tab)))

(ert-deftest kuro-input-keymap--g18-send-shifted-return-is-interactive ()
  "`kuro--send-shifted-return' must be an interactive command."
  (should (commandp #'kuro--send-shifted-return)))

;;; Group 19: kuro--def-shifted-key macro — generated commands

(kuro-input-keymap-test--deftest-generated-shifted-key-cases)

(kuro-input-keymap-test--deftest-generated-shifted-key-interactive
 kuro-input-keymap--g19-shifted-key-table-all-interactive)

;;; Group 20: kuro--def-shifted-key macro — structural coverage

(ert-deftest kuro-input-keymap-def-shifted-key-expands-to-defun ()
  "`kuro--def-shifted-key' single-step expands to a `defun' form."
  (let ((exp (macroexpand-1
              '(kuro--def-shifted-key kuro-test--sk "\e[9;2u" "\e[Z" "doc"))))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-test--sk))))

(ert-deftest kuro-input-keymap-def-shifted-key-expansion-has-interactive ()
  "`kuro--def-shifted-key' expansion contains `(interactive)'."
  (let ((exp (macroexpand-1
              '(kuro--def-shifted-key kuro-test--sk2 "\e[13;2u" "\r" "doc"))))
    (should (member '(interactive) (cddr exp)))))

(ert-deftest kuro-input-keymap-def-shifted-key-expansion-no-args ()
  "`kuro--def-shifted-key' generated function has an empty arglist (no parameters)."
  (let* ((exp (macroexpand-1
               '(kuro--def-shifted-key kuro-test--sk3 "\e[Z" "\e[Z" "doc")))
         (arglist (caddr exp)))
    (should (null arglist))))

(ert-deftest kuro-input-keymap-apply-exceptions-non-meta-clears-binding-only ()
  "`kuro--keymap-apply-exceptions' clears a non-M-* binding without touching ESC+char."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions '("C-g")))
    (define-key km (kbd "C-g") #'ignore)
    (kuro--keymap-apply-exceptions km)
    ;; The C-g binding must be cleared.
    (should-not (lookup-key km (kbd "C-g")))))

(ert-deftest kuro-input-keymap-apply-exceptions-multi-char-meta-no-esc-fallback ()
  "`kuro--keymap-apply-exceptions' handles M-<multi-char> without touching ESC+char.
When the part after \"M-\" is more than one char (e.g. \"M-C-f\"), `char' is nil
and the inner `(when char ...)' branch is skipped — no ESC+char clear attempt."
  (let ((km (make-sparse-keymap))
        (kuro-keymap-exceptions '("M-C-f")))
    (define-key km (kbd "M-C-f") #'ignore)
    ;; Must not error — the (when char) guard must prevent the (aref rest 0) call.
    (should-not (condition-case err
                    (progn (kuro--keymap-apply-exceptions km) nil)
                  (error err)))))

(provide 'kuro-input-keymap-test-4)
;;; kuro-input-keymap-test-4.el ends here
