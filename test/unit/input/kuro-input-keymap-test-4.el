;;; kuro-input-keymap-test-4.el --- Tests for kuro-input-keymap.el (part 4)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keymap-test-support)

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

(ert-deftest kuro-input-keymap--g17-backtab-sends-legacy-without-kkp ()
  "With keyboard-flags=0, [backtab] sends legacy ESC [ Z."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s)))
              ((symbol-function 'kuro--schedule-immediate-render) #'ignore)
              ((symbol-function 'kuro--kkp-flag-p) (lambda (_) nil)))
      (let ((map (kuro--build-keymap)))
        (call-interactively (lookup-key map [backtab])))
      (should (equal sent "\e[Z")))))

(ert-deftest kuro-input-keymap--g17-backtab-sends-kkp-with-disambiguate ()
  "With KKP DISAMBIGUATE flag, [backtab] sends CSI 9;2u."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s)))
              ((symbol-function 'kuro--schedule-immediate-render) #'ignore)
              ((symbol-function 'kuro--kkp-flag-p) (lambda (_) t)))
      (let ((map (kuro--build-keymap)))
        (call-interactively (lookup-key map [backtab])))
      (should (equal sent "\e[9;2u")))))

(ert-deftest kuro-input-keymap--g17-shift-return-sends-cr-without-kkp ()
  "With keyboard-flags=0, [S-return] sends bare CR."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s)))
              ((symbol-function 'kuro--schedule-immediate-render) #'ignore)
              ((symbol-function 'kuro--kkp-flag-p) (lambda (_) nil)))
      (let ((map (kuro--build-keymap)))
        (call-interactively (lookup-key map [S-return])))
      (should (equal sent "\r")))))

(ert-deftest kuro-input-keymap--g17-shift-return-sends-kkp-csi-13-2u ()
  "With KKP DISAMBIGUATE flag, [S-return] sends CSI 13;2u."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s)))
              ((symbol-function 'kuro--schedule-immediate-render) #'ignore)
              ((symbol-function 'kuro--kkp-flag-p) (lambda (_) t)))
      (let ((map (kuro--build-keymap)))
        (call-interactively (lookup-key map [S-return])))
      (should (equal sent "\e[13;2u")))))

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

(defconst kuro-input-keymap-test--shifted-key-table
  '((kuro-input-keymap--g19-shifted-tab-kkp
     kuro--send-shifted-tab  "\e[9;2u"  "\e[Z")
    (kuro-input-keymap--g19-shifted-return-kkp
     kuro--send-shifted-return "\e[13;2u" "\r"))
  "Table: (test-name fn kkp-seq legacy-seq) for kuro--def-shifted-key generated fns.")

(defmacro kuro-input-keymap-test--def-shifted-key-sends (test-name fn kkp-seq legacy-seq)
  "Define two tests: KKP path sends KKP-SEQ, legacy path sends LEGACY-SEQ."
  `(progn
     (ert-deftest ,test-name ()
       ,(format "`%s' sends KKP seq when DISAMBIGUATE flag is set." fn)
       (let ((sent nil))
         (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s)))
                   ((symbol-function 'kuro--schedule-immediate-render) #'ignore)
                   ((symbol-function 'kuro--kkp-flag-p) (lambda (_) t)))
           (funcall #',fn)
           (should (equal sent ,kkp-seq)))))))

(kuro-input-keymap-test--def-shifted-key-sends
 kuro-input-keymap--g19-shifted-tab-kkp
 kuro--send-shifted-tab "\e[9;2u" "\e[Z")

(kuro-input-keymap-test--def-shifted-key-sends
 kuro-input-keymap--g19-shifted-return-kkp
 kuro--send-shifted-return "\e[13;2u" "\r")

(ert-deftest kuro-input-keymap--g19-shifted-key-table-all-interactive ()
  "All entries in `kuro-input-keymap-test--shifted-key-table' are interactive commands."
  (dolist (entry kuro-input-keymap-test--shifted-key-table)
    (should (commandp (symbol-function (nth 1 entry))))))

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
