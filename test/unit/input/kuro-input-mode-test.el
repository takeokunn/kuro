;;; kuro-input-mode-test.el --- Tests for kuro-input-mode.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the three-mode input system (char/semi-char/line).
;; These tests run without the Rust module by using kuro-test-stubs.

;;; Code:

(require 'kuro-input-mode-test-support)


;;; Group 1 — Initial state

(ert-deftest kuro-input-mode-test-initial-mode-is-semi-char ()
  "New kuro-mode buffer starts in semi-char mode."
  (kuro-input-mode-test--with-buffer
   (should (eq kuro--input-mode 'semi-char))))

(ert-deftest kuro-input-mode-test-initial-line-buffer-empty ()
  "Line buffer is empty in a new buffer."
  (kuro-input-mode-test--with-buffer
   (should (string= kuro--line-buffer ""))))

(ert-deftest kuro-input-mode-test-initial-overlay-nil ()
  "Line overlay is nil in a new buffer."
  (kuro-input-mode-test--with-buffer
   (should (null kuro--line-overlay))))


;;; Group 2 — Mode-line lighter

(ert-deftest kuro-input-mode-test-lighter-semi-char ()
  "`kuro--input-mode-lighter' returns \" [S]\" in semi-char mode."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'semi-char)
   (should (string= (kuro--input-mode-lighter) " [S]"))))

(ert-deftest kuro-input-mode-test-lighter-char ()
  "`kuro--input-mode-lighter' returns \" [C]\" in char mode."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'char)
   (should (string= (kuro--input-mode-lighter) " [C]"))))

(ert-deftest kuro-input-mode-test-lighter-line ()
  "`kuro--input-mode-lighter' returns \" [L]\" in line mode."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (should (string= (kuro--input-mode-lighter) " [L]"))))

(ert-deftest kuro-input-mode-test-lighter-unknown ()
  "`kuro--input-mode-lighter' returns \"\" for unknown mode values."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'unknown-mode)
   (should (string= (kuro--input-mode-lighter) ""))))

(ert-deftest kuro-input-mode-test-lighter-alist-covers-all-modes ()
  "`kuro--input-mode-lighter-alist' contains entries for all three input modes."
  (should (assq 'char      kuro--input-mode-lighter-alist))
  (should (assq 'semi-char kuro--input-mode-lighter-alist))
  (should (assq 'line      kuro--input-mode-lighter-alist)))

(ert-deftest kuro-input-mode-test-lighter-alist-values-are-strings ()
  "All lighter strings in the alist are non-empty strings."
  (dolist (entry kuro--input-mode-lighter-alist)
    (should (stringp (cdr entry)))
    (should (> (length (cdr entry)) 0))))


;;; Group 3 — kuro--build-keymap builds both keymaps

(ert-deftest kuro-input-mode-test-build-keymap-produces-char-keymap ()
  "`kuro--build-keymap' sets `kuro--char-keymap' to a non-nil keymap."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (should (keymapp kuro--char-keymap))))

(ert-deftest kuro-input-mode-test-build-keymap-produces-semi-char-keymap ()
  "`kuro--build-keymap' sets `kuro--keymap' to a non-nil keymap."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (should (keymapp kuro--keymap))))

(ert-deftest kuro-input-mode-test-char-keymap-binds-self-insert ()
  "`kuro--char-keymap' remaps `self-insert-command' (no exceptions)."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (should (eq (lookup-key kuro--char-keymap [remap self-insert-command])
               #'kuro--self-insert))))

(ert-deftest kuro-input-mode-test-semi-char-keymap-lacks-M-x ()
  "`kuro--keymap' (semi-char) does NOT bind M-x (it falls through to Emacs)."
  (kuro-input-mode-test--with-buffer
   ;; Ensure M-x is in exceptions
   (let ((kuro-keymap-exceptions (cons "M-x" kuro-keymap-exceptions)))
     (kuro--build-keymap)
     ;; nil means unbound → falls through to global keymap
     (should (null (lookup-key kuro--keymap (kbd "M-x")))))))

(ert-deftest kuro-input-mode-test-char-keymap-binds-M-x ()
  "`kuro--char-keymap' (char mode) DOES bind M-x (forwards to PTY as ESC x)."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   ;; In char keymap M-x should be bound to a lambda that sends meta
   (should (lookup-key kuro--char-keymap (kbd "M-x")))))


;;; Group 4 — Line buffer operations

(ert-deftest kuro-input-mode-test-line-self-insert-appends ()
  "`kuro--line-self-insert' appends `last-command-event' to the buffer."
  (kuro-input-mode-test--with-line "" 0
   (setq last-command-event ?a)
   (kuro--line-self-insert)
   (should (string= kuro--line-buffer "a"))))

(ert-deftest kuro-input-mode-test-line-self-insert-accumulates ()
  "Multiple `kuro--line-self-insert' calls accumulate in order."
  (kuro-input-mode-test--with-line "" 0
   (dolist (ch '(?h ?e ?l ?l ?o))
     (setq last-command-event ch)
     (kuro--line-self-insert))
   (should (string= kuro--line-buffer "hello"))))

(ert-deftest kuro-input-mode-test-line-self-insert-ignores-non-char ()
  "`kuro--line-self-insert' ignores non-character events."
  (kuro-input-mode-test--with-line "" 0
   (setq last-command-event 'f1)  ; symbol, not character
   (kuro--line-self-insert)
   (should (string= kuro--line-buffer ""))))

(ert-deftest kuro-input-mode-test-line-delete-removes-last-char ()
  "`kuro--line-delete' removes the last character."
  (kuro-input-mode-test--with-line "hello" 5
   (kuro--line-delete)
   (should (string= kuro--line-buffer "hell"))))

(ert-deftest kuro-input-mode-test-line-delete-noop-on-empty ()
  "`kuro--line-delete' is a no-op when buffer is empty."
  (kuro-input-mode-test--with-line "" 0
   (kuro--line-delete)
   (should (string= kuro--line-buffer ""))))

(ert-deftest kuro-input-mode-test-line-kill-line-clears ()
  "`kuro--line-kill-line' clears the entire buffer."
  (kuro-input-mode-test--with-line "hello world" 0
   (kuro--line-kill-line)
   (should (string= kuro--line-buffer ""))))

(ert-deftest kuro-input-mode-test-line-abort-clears-and-messages ()
  "`kuro--line-abort' clears buffer and displays a message."
  (kuro-input-mode-test--with-line "partial" 7
   (kuro--line-abort)
   (should (string= kuro--line-buffer ""))))


;;; Group 5 — Line commit sends correct sequence

(ert-deftest kuro-input-mode-test-line-commit-sends-text-plus-cr ()
  "`kuro--line-commit' sends accumulated text followed by carriage return."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "ls -la")
   (let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (setq sent s)))
               ((symbol-function 'kuro--schedule-immediate-render)
                #'ignore))
       (kuro--line-commit)
       (should (string= sent "ls -la\r"))))))

(ert-deftest kuro-input-mode-test-line-commit-clears-buffer ()
  "`kuro--line-commit' clears `kuro--line-buffer' after sending."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "hello")
   (cl-letf (((symbol-function 'kuro--send-key)    #'ignore)
             ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
     (kuro--line-commit)
     (should (string= kuro--line-buffer "")))))

(ert-deftest kuro-input-mode-test-line-commit-empty-sends-only-cr ()
  "`kuro--line-commit' on empty buffer sends only carriage return."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "")
   (let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (setq sent s)))
               ((symbol-function 'kuro--schedule-immediate-render)
                #'ignore))
       (kuro--line-commit)
       (should (string= sent "\r"))))))


;;; Group 6 — Overlay lifecycle

(ert-deftest kuro-input-mode-test-overlay-created-in-line-mode ()
  "`kuro--line-mode-update-display' creates an overlay in line mode."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "hi")
   (kuro--line-mode-update-display)
   (should (overlayp kuro--line-overlay))))

(ert-deftest kuro-input-mode-test-overlay-not-created-outside-line-mode ()
  "`kuro--line-mode-update-display' does not create overlay in non-line modes."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'semi-char)
   (setq kuro--line-buffer "hi")
   (kuro--line-mode-update-display)
   (should (null kuro--line-overlay))))

(ert-deftest kuro-input-mode-test-overlay-cleared-on-abort ()
  "`kuro--line-abort' removes the overlay."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "test")
   (kuro--line-mode-update-display)
   (should (overlayp kuro--line-overlay))
   (kuro--line-abort)
   (should (null kuro--line-overlay))))

(ert-deftest kuro-input-mode-test-overlay-cleared-on-commit ()
  "`kuro--line-commit' removes the overlay."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "test")
   (kuro--line-mode-update-display)
   (should (overlayp kuro--line-overlay))
   (cl-letf (((symbol-function 'kuro--send-key)    #'ignore)
             ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
     (kuro--line-commit)
     (should (null kuro--line-overlay)))))

(provide 'kuro-input-mode-test)
;;; kuro-input-mode-test.el ends here
