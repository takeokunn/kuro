;;; kuro-input-mode-test-2.el --- kuro-input-mode-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-mode-test-support)

;;; Group 7 — Mode switching commands

(ert-deftest kuro-input-mode-test-kuro-char-mode-sets-mode ()
  "`kuro-char-mode' sets `kuro--input-mode' to `char'."
  (kuro-input-mode-test--with-buffer
   (kuro-char-mode)
   (should (eq kuro--input-mode 'char))))

(ert-deftest kuro-input-mode-test-kuro-semi-char-mode-sets-mode ()
  "`kuro-semi-char-mode' sets `kuro--input-mode' to `semi-char'."
  (kuro-input-mode-test--with-buffer
   (kuro-char-mode)
   (kuro-semi-char-mode)
   (should (eq kuro--input-mode 'semi-char))))

(ert-deftest kuro-input-mode-test-kuro-line-mode-sets-mode ()
  "`kuro-line-mode' sets `kuro--input-mode' to `line'."
  (kuro-input-mode-test--with-buffer
   (kuro-line-mode)
   (should (eq kuro--input-mode 'line))))

(ert-deftest kuro-input-mode-test-kuro-char-mode-clears-line-buffer ()
  "`kuro-char-mode' clears any accumulated line buffer."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "leftover")
   (kuro-char-mode)
   (should (string= kuro--line-buffer ""))))

(ert-deftest kuro-input-mode-test-kuro-semi-char-mode-clears-line-buffer ()
  "`kuro-semi-char-mode' clears any accumulated line buffer."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "leftover")
   (kuro-semi-char-mode)
   (should (string= kuro--line-buffer ""))))

(ert-deftest kuro-input-mode-test-kuro-line-mode-clears-line-buffer ()
  "`kuro-line-mode' resets the line buffer on entry."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "stale")
   (kuro-line-mode)
   (should (string= kuro--line-buffer ""))))

(ert-deftest kuro-input-mode-test-kuro-char-mode-fails-outside-kuro ()
  "`kuro-char-mode' signals `user-error' outside a kuro-mode buffer."
  (with-temp-buffer
   (should-error (kuro-char-mode) :type 'user-error)))

(ert-deftest kuro-input-mode-test-kuro-line-mode-fails-outside-kuro ()
  "`kuro-line-mode' signals `user-error' outside a kuro-mode buffer."
  (with-temp-buffer
   (should-error (kuro-line-mode) :type 'user-error)))


;;; Group 8 — kuro-cycle-input-mode

(ert-deftest kuro-input-mode-test-cycle-semi-char-to-char ()
  "Cycling from semi-char mode moves to char mode."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'semi-char)
   (kuro-cycle-input-mode)
   (should (eq kuro--input-mode 'char))))

(ert-deftest kuro-input-mode-test-cycle-char-to-line ()
  "Cycling from char mode moves to line mode."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'char)
   (kuro-cycle-input-mode)
   (should (eq kuro--input-mode 'line))))

(ert-deftest kuro-input-mode-test-cycle-line-to-semi-char ()
  "Cycling from line mode returns to semi-char mode."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (kuro-cycle-input-mode)
   (should (eq kuro--input-mode 'semi-char))))

(ert-deftest kuro-input-mode-test-cycle-full-round-trip ()
  "Three full cycles returns to the original mode."
  (kuro-input-mode-test--with-buffer
   (should (eq kuro--input-mode 'semi-char))
   (kuro-cycle-input-mode)  ; → char
   (kuro-cycle-input-mode)  ; → line
   (kuro-cycle-input-mode)  ; → semi-char
   (should (eq kuro--input-mode 'semi-char))))

(ert-deftest kuro-input-mode-test-cycle-fails-outside-kuro ()
  "`kuro-cycle-input-mode' signals `user-error' outside a kuro-mode buffer."
  (with-temp-buffer
   (should-error (kuro-cycle-input-mode) :type 'user-error)))


;;; Group 9 — Line mode keymap shape

(ert-deftest kuro-input-mode-test-line-keymap-binds-commit ()
  "`kuro--line-mode-keymap' binds [return] to `kuro--line-commit'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap [return])
               #'kuro--line-commit))))

(ert-deftest kuro-input-mode-test-line-keymap-binds-delete ()
  "`kuro--line-mode-keymap' binds [backspace] to `kuro--line-delete'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap [backspace])
               #'kuro--line-delete))))

(ert-deftest kuro-input-mode-test-line-keymap-binds-abort ()
  "`kuro--line-mode-keymap' binds C-g to `kuro--line-abort'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-g"))
               #'kuro--line-abort))))

(ert-deftest kuro-input-mode-test-line-keymap-binds-kill-line ()
  "`kuro--line-mode-keymap' binds C-k to `kuro--line-kill-line'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-k"))
               #'kuro--line-kill-line))))

(ert-deftest kuro-input-mode-test-line-keymap-remaps-self-insert ()
  "`kuro--line-mode-keymap' remaps `self-insert-command' to `kuro--line-self-insert'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap
                           [remap self-insert-command])
               #'kuro--line-self-insert))))

(ert-deftest kuro-input-mode-test-line-keymap-binds-minibuffer-send ()
  "`kuro--line-mode-keymap' binds C-c C-r to `kuro-line-minibuffer-send'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-c C-r"))
               #'kuro-line-minibuffer-send))))


;;; Group 10 — Minibuffer path (IME support)

(ert-deftest kuro-input-mode-test-minibuffer-send-sends-text-plus-cr ()
  "`kuro-line-minibuffer-send' sends the minibuffer result followed by CR."
  (kuro-input-mode-test--with-buffer
   (let ((sent nil))
     (cl-letf (((symbol-function 'read-from-minibuffer)
                (lambda (&rest _) "ls -la"))
               ((symbol-function 'kuro--send-key)
                (lambda (s) (setq sent s)))
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro-line-minibuffer-send)
       (should (string= sent "ls -la\r"))))))

(ert-deftest kuro-input-mode-test-minibuffer-send-clears-buffer ()
  "`kuro-line-minibuffer-send' clears `kuro--line-buffer' after sending."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "partial")
   (cl-letf (((symbol-function 'read-from-minibuffer)
              (lambda (&rest _) "done"))
             ((symbol-function 'kuro--send-key)    #'ignore)
             ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
     (kuro-line-minibuffer-send)
     (should (string= kuro--line-buffer "")))))

(ert-deftest kuro-input-mode-test-minibuffer-send-passes-history-arg ()
  "`kuro-line-minibuffer-send' passes `kuro--line-history' to `read-from-minibuffer'."
  (kuro-input-mode-test--with-buffer
   (let ((hist-arg :unset))
     (cl-letf (((symbol-function 'read-from-minibuffer)
                (lambda (_prompt _init _map _read hist &rest _)
                  (setq hist-arg hist)
                  ""))
               ((symbol-function 'kuro--send-key)    #'ignore)
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro-line-minibuffer-send)
       (should (eq hist-arg 'kuro--line-history))))))

(ert-deftest kuro-input-mode-test-minibuffer-send-quit-does-not-send ()
  "C-g in minibuffer (quit signal) does not send anything to PTY."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "partial")
   (let ((sent nil))
     (cl-letf (((symbol-function 'read-from-minibuffer)
                (lambda (&rest _) (signal 'quit nil)))
               ((symbol-function 'kuro--send-key)
                (lambda (s) (setq sent s)))
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro-line-minibuffer-send)
       (should (null sent))
       (should (string= kuro--line-buffer ""))))))

(ert-deftest kuro-input-mode-test-minibuffer-send-fails-outside-kuro ()
  "`kuro-line-minibuffer-send' signals `user-error' outside a kuro buffer."
  (with-temp-buffer
   (should-error (kuro-line-minibuffer-send) :type 'user-error)))

(ert-deftest kuro-input-mode-test-use-minibuffer-nil-accumulates-overlay ()
  "With `kuro-line-use-minibuffer' nil, `kuro--line-self-insert' appends to buffer."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (let ((kuro-line-use-minibuffer nil))
     (setq last-command-event ?a)
     (kuro--line-self-insert)
     (should (string= kuro--line-buffer "a")))))

(ert-deftest kuro-input-mode-test-use-minibuffer-t-delegates-to-minibuffer ()
  "With `kuro-line-use-minibuffer' t, `kuro--line-self-insert' delegates to minibuffer send."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (let ((kuro-line-use-minibuffer t)
         (called nil))
     (cl-letf (((symbol-function 'kuro-line-minibuffer-send)
                (lambda () (setq called t))))
       (setq last-command-event ?a)
       (kuro--line-self-insert)
       (should called)))))

;;; Group 11 — Line-mode history navigation (overlay path)

(ert-deftest kuro-input-mode-test-history-prev-noop-when-empty ()
  "`kuro--line-history-prev' is a no-op when `kuro--line-history' is nil."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history nil))
     (setq kuro--line-buffer "draft")
     (kuro--line-history-prev)
     (should (string= kuro--line-buffer "draft"))
     (should (= kuro--line-history-idx -1)))))

(ert-deftest kuro-input-mode-test-history-prev-stashes-buffer ()
  "First M-p stashes `kuro--line-buffer' into `kuro--line-history-stash'."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("cmd2" "cmd1")))
     (setq kuro--line-buffer "draft")
     (kuro--line-history-prev)
     (should (string= kuro--line-history-stash "draft")))))

(ert-deftest kuro-input-mode-test-history-prev-shows-first-entry ()
  "First M-p sets `kuro--line-buffer' to the most-recent history entry."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("cmd2" "cmd1")))
     (setq kuro--line-buffer "draft")
     (kuro--line-history-prev)
     (should (string= kuro--line-buffer "cmd2"))
     (should (= kuro--line-history-idx 0)))))

(ert-deftest kuro-input-mode-test-history-prev-clamps-at-oldest ()
  "Multiple M-p at the oldest entry does not go beyond the last entry."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("cmd2" "cmd1")))
     (setq kuro--line-buffer "draft")
     (kuro--line-history-prev)  ; idx → 0
     (kuro--line-history-prev)  ; idx → 1
     (kuro--line-history-prev)  ; should clamp at 1
     (should (= kuro--line-history-idx 1))
     (should (string= kuro--line-buffer "cmd1")))))

(ert-deftest kuro-input-mode-test-history-next-noop-at-bottom ()
  "`kuro--line-history-next' when idx==-1 does nothing."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("cmd2" "cmd1")))
     (setq kuro--line-buffer "draft")
     (kuro--line-history-next)
     (should (string= kuro--line-buffer "draft"))
     (should (= kuro--line-history-idx -1)))))

(ert-deftest kuro-input-mode-test-history-next-restores-stash ()
  "M-n when idx==0 restores `kuro--line-history-stash' into `kuro--line-buffer'."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("cmd2" "cmd1")))
     (setq kuro--line-buffer "draft")
     (kuro--line-history-prev)  ; idx → 0, stash = "draft"
     (kuro--line-history-next)  ; idx → -1, restore stash
     (should (string= kuro--line-buffer "draft")))))

(ert-deftest kuro-input-mode-test-history-next-resets-idx ()
  "M-n when idx==0 resets `kuro--line-history-idx' back to -1."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("cmd2" "cmd1")))
     (setq kuro--line-buffer "draft")
     (kuro--line-history-prev)  ; idx → 0
     (kuro--line-history-next)  ; idx → -1
     (should (= kuro--line-history-idx -1)))))

(ert-deftest kuro-input-mode-test-commit-pushes-to-history ()
  "`kuro--line-commit' with non-empty buffer pushes text to `kuro--line-history'."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "ls -la")
   (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
             ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
     (kuro--line-commit)
     (should (member "ls -la" kuro--line-history)))))

(ert-deftest kuro-input-mode-test-commit-empty-does-not-push ()
  "`kuro--line-commit' with empty buffer does NOT push to history."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "")
   (let ((history-before kuro--line-history))
     (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro--line-commit)
       (should (equal kuro--line-history history-before))))))

(ert-deftest kuro-input-mode-test-commit-resets-history-idx ()
  "`kuro--line-commit' resets `kuro--line-history-idx' to -1."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "echo hi")
   (setq kuro--line-history-idx 2)
   (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
             ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
     (kuro--line-commit)
     (should (= kuro--line-history-idx -1)))))

;;; Group 12 — savehist integration

(ert-deftest kuro-input-mode-test-savehist-setup-registers-history ()
  "`kuro-input-mode-savehist-setup' adds kuro--line-history to savehist."
  (require 'savehist)
  (let ((savehist-additional-variables nil))
    (kuro-input-mode-savehist-setup)
    (should (memq 'kuro--line-history savehist-additional-variables))))

(ert-deftest kuro-input-mode-test-savehist-setup-idempotent ()
  "`kuro-input-mode-savehist-setup' does not add duplicates."
  (require 'savehist)
  (let ((savehist-additional-variables '(kuro--line-history)))
    (kuro-input-mode-savehist-setup)
    (should (= (length (seq-filter (lambda (v) (eq v 'kuro--line-history))
                                   savehist-additional-variables))
               1))))

;;; Group 13 — kuro-line-history-max-length truncation

(ert-deftest kuro-input-mode-test-history-max-length-defcustom-exists ()
  "`kuro-line-history-max-length' is a defined customization variable."
  (should (boundp 'kuro-line-history-max-length)))

(ert-deftest kuro-input-mode-test-commit-truncates-at-max ()
  "`kuro--line-commit' truncates history when it exceeds the max length."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("b" "a"))
         (kuro-line-history-max-length 2))
     (setq kuro--line-buffer "c")
     (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro--line-commit)
       ;; Pushed: ("c" "b" "a") → truncated to max 2 → ("c" "b")
       (should (= (length kuro--line-history) 2))
       (should (string= (car kuro--line-history) "c"))
       (should (string= (cadr kuro--line-history) "b"))))))

(ert-deftest kuro-input-mode-test-commit-no-truncate-under-max ()
  "`kuro--line-commit' does NOT truncate when history stays at or under max."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("a"))
         (kuro-line-history-max-length 5))
     (setq kuro--line-buffer "b")
     (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro--line-commit)
       (should (= (length kuro--line-history) 2))))))

(ert-deftest kuro-input-mode-test-commit-max-nil-keeps-all ()
  "`kuro--line-commit' keeps the full history when max-length is nil."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history (make-list 200 "x"))
         (kuro-line-history-max-length nil))
     (setq kuro--line-buffer "y")
     (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro--line-commit)
       (should (= (length kuro--line-history) 201))))))


;;; Group 16 — kuro--line-mode-bindings table invariants

(ert-deftest kuro-input-mode-test-line-mode-bindings-all-symbols-bound ()
  "Every command in `kuro--line-mode-bindings' must be a bound function symbol."
  (dolist (b kuro--line-mode-bindings)
    (should (fboundp (cdr b)))))

(ert-deftest kuro-input-mode-test-line-mode-bindings-non-empty ()
  "`kuro--line-mode-bindings' must have at least 30 entries."
  (should (>= (length kuro--line-mode-bindings) 30)))

(ert-deftest kuro-input-mode-test-line-mode-bindings-installs-all ()
  "`kuro--build-line-mode-keymap' installs every entry from `kuro--line-mode-bindings'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (dolist (b kuro--line-mode-bindings)
     (should (eq (lookup-key kuro--line-mode-keymap (kbd (car b)))
                 (cdr b))))))


(provide 'kuro-input-mode-test-2)

;;; kuro-input-mode-test-2.el ends here
