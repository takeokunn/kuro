;;; kuro-input-keymap-test-cases.el --- Keymap test case data  -*- lexical-binding: t; -*-

;;; Code:

(defconst kuro-input-keymap-test--setup-binding-cases
  '((kuro-input-keymap-setup-navigation-arrow-keys-bound
     kuro--keymap-setup-navigation
     (([up] :present)
      ([down] :present)
      ([left] :present)
      ([right] :present)))
    (kuro-input-keymap-setup-navigation-home-end-bound
     kuro--keymap-setup-navigation
     (([home] kuro--HOME)
      ([end] kuro--END)))
    (kuro-input-keymap-setup-navigation-page-keys-bound
     kuro--keymap-setup-navigation
     (([prior] kuro--PAGE-UP)
      ([next] kuro--PAGE-DOWN)))
    (kuro-input-keymap-setup-navigation-insert-delete-bound
     kuro--keymap-setup-navigation
     (([insert] kuro--INSERT)
      ([delete] kuro--DELETE)))
    (kuro-input-keymap-setup-navigation-scrollback-keys-bound
     kuro--keymap-setup-navigation
     (([S-prior] kuro-scroll-up)
      ([S-next] kuro-scroll-down)
      ([S-end] kuro-scroll-bottom)))
    (kuro-input-keymap-setup-mouse-down-mouse-1-bound
     kuro--keymap-setup-mouse
     (([down-mouse-1] kuro--mouse-press)))
    (kuro-input-keymap-setup-mouse-mouse-1-bound
     kuro--keymap-setup-mouse
     (([mouse-1] kuro--mouse-release)))
    (kuro-input-keymap-setup-mouse-mouse-4-scroll-up-bound
     kuro--keymap-setup-mouse
     (([mouse-4] kuro--mouse-scroll-up)))
    (kuro-input-keymap-setup-mouse-mouse-5-scroll-down-bound
     kuro--keymap-setup-mouse
     (([mouse-5] kuro--mouse-scroll-down)))
    (kuro-input-keymap-setup-mouse-all-three-buttons-press-bound
     kuro--keymap-setup-mouse
     (([down-mouse-2] kuro--mouse-press)
      ([down-mouse-3] kuro--mouse-press)))
    (kuro-input-keymap-setup-mouse-all-three-buttons-release-bound
     kuro--keymap-setup-mouse
     (([mouse-2] kuro--mouse-release)
      ([mouse-3] kuro--mouse-release)))
    (kuro-input-keymap-setup-yank-remap-yank-bound
     kuro--keymap-setup-yank
     (([remap yank] kuro--yank)))
    (kuro-input-keymap-setup-yank-remap-yank-pop-bound
     kuro--keymap-setup-yank
     (([remap yank-pop] kuro--yank-pop)))
    (kuro-input-keymap-setup-yank-remap-clipboard-yank-bound
     kuro--keymap-setup-yank
     (([remap clipboard-yank] kuro--yank))))
  "Table of (test-name setup-fn binding-specs) for setup binding tests.")

(defconst kuro-input-keymap-test--shifted-key-send-cases
  '((kuro-input-keymap--g17-backtab-sends-legacy-without-kkp
     [backtab] nil "\e[Z")
    (kuro-input-keymap--g17-backtab-sends-kkp-with-disambiguate
     [backtab] t "\e[9;2u")
    (kuro-input-keymap--g17-shift-return-sends-cr-without-kkp
     [S-return] nil "\r")
    (kuro-input-keymap--g17-shift-return-sends-kkp-csi-13-2u
     [S-return] t "\e[13;2u"))
  "Table of (test-name key kkp-enabled expected-sequence) for shifted key bindings.")

(defconst kuro-input-keymap-test--generated-shifted-key-cases
  '((kuro-input-keymap--g19-shifted-tab-kkp
     kuro--send-shifted-tab "\e[9;2u")
    (kuro-input-keymap--g19-shifted-return-kkp
     kuro--send-shifted-return "\e[13;2u"))
  "Table of (test-name command kkp-sequence) for generated shifted-key commands.")

(eval-and-compile
  (defconst kuro-input-keymap-test--built-binding-cases
    '((kuro-input-keymap-build-c-m-is-ret
       (kbd "C-m") kuro--RET)
      (kuro-input-keymap-build-c-i-is-tab
       (kbd "C-i") kuro--TAB)
      (kuro-input-keymap-build-c-h-is-del
       (kbd "C-h") kuro--DEL)
      (kuro-input-keymap-build-del-is-del
       (kbd "DEL") kuro--DEL)
      (kuro-input-keymap-build-m-del-bound-to-meta-backspace
       (kbd "M-DEL") kuro--send-meta-backspace)
      (kuro-input-keymap-build-m-backspace-bound-to-meta-backspace
       (kbd "M-<backspace>") kuro--send-meta-backspace))
    "Table of (test-name key expected) for built keymap binding equality checks.")

  (defconst kuro-input-keymap-test--built-live-binding-cases
    '((kuro-input-keymap-escape-bound-is-live [escape])
      (kuro-input-keymap-c-a-is-live (kbd "C-a"))
      (kuro-input-keymap-c-z-is-live (kbd "C-z"))
      (kuro-input-keymap-m-0-is-bound (kbd "M-0"))
      (kuro-input-keymap-m-9-is-bound (kbd "M-9"))
      (kuro-input-keymap-esc-letter-two-key-fallback-is-bound (vector ?\e ?a))
      (kuro-input-keymap-esc-letter-two-key-upper-fallback-is-bound (vector ?\e ?Z)))
    "Table of (test-name key) for built keymap presence checks.")

  (defconst kuro-input-keymap-test--built-send-cases
    '((kuro-input-keymap-escape-sends-ctrl-27
       [escape] kuro--send-ctrl 27)
      (kuro-input-keymap-c-a-sends-ctrl-1
       (kbd "C-a") kuro--send-ctrl 1)
      (kuro-input-keymap-c-z-sends-ctrl-26
       (kbd "C-z") kuro--send-ctrl 26)
      (kuro-input-keymap-m-digits-send-correct-char
       (kbd "M-5") kuro--send-meta ?5)
      (kuro-input-keymap-esc-letter-two-key-sends-correct-char
       (vector ?\e ?b) kuro--send-meta ?b))
    "Table of (test-name key sender-fn arg) for built keymap send checks."))

(provide 'kuro-input-keymap-test-cases)
;;; kuro-input-keymap-test-cases.el ends here
