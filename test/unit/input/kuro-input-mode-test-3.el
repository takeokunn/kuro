;;; kuro-input-mode-test-3.el --- kuro-input-mode-test (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-mode-test-support)

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


;;; Group 17 — kuro--apply-input-mode keymap dispatch

(ert-deftest kuro-input-mode-test-apply-char-mode-uses-char-keymap ()
  "`kuro--apply-input-mode' sets `kuro--char-keymap' as the parent and activates kuro-mode-map in char mode."
  (kuro-input-mode-test--with-buffer
   (let ((parent-set-to nil)
         (local-map-set-to nil))
     (cl-letf (((symbol-function 'set-keymap-parent)
                (lambda (_map parent) (setq parent-set-to parent)))
               ((symbol-function 'use-local-map)
                (lambda (m) (setq local-map-set-to m)))
               ((symbol-function 'force-mode-line-update) #'ignore))
       (setq kuro--input-mode 'char)
       (kuro--apply-input-mode)
       (should (eq parent-set-to kuro--char-keymap))
       (should (eq local-map-set-to kuro-mode-map))))))

(ert-deftest kuro-input-mode-test-apply-semi-char-mode-uses-base-keymap ()
  "`kuro--apply-input-mode' sets `kuro--keymap' as the parent in semi-char mode."
  (kuro-input-mode-test--with-buffer
   (let ((parent-set-to nil))
     (cl-letf (((symbol-function 'set-keymap-parent)
                (lambda (_map parent) (setq parent-set-to parent)))
               ((symbol-function 'use-local-map) #'ignore)
               ((symbol-function 'force-mode-line-update) #'ignore))
       (setq kuro--input-mode 'semi-char)
       (kuro--apply-input-mode)
       (should (eq parent-set-to kuro--keymap))))))

(ert-deftest kuro-input-mode-test-apply-line-mode-builds-keymap ()
  "`kuro--apply-input-mode' calls `kuro--build-line-mode-keymap' in line mode."
  (kuro-input-mode-test--with-buffer
   (let ((build-called nil))
     (cl-letf (((symbol-function 'kuro--build-line-mode-keymap)
                (lambda () (setq build-called t)))
               ((symbol-function 'use-local-map) #'ignore)
               ((symbol-function 'make-composed-keymap) (lambda (&rest _) (make-sparse-keymap)))
               ((symbol-function 'force-mode-line-update) #'ignore))
       (setq kuro--input-mode 'line)
       (kuro--apply-input-mode)
       (should build-called)))))

(ert-deftest kuro-input-mode-test-apply-always-calls-force-mode-line-update ()
  "`kuro--apply-input-mode' always calls `force-mode-line-update' regardless of mode."
  (kuro-input-mode-test--with-buffer
   (let ((update-called nil))
     (cl-letf (((symbol-function 'set-keymap-parent) #'ignore)
               ((symbol-function 'use-local-map) #'ignore)
               ((symbol-function 'force-mode-line-update)
                (lambda () (setq update-called t))))
       (setq kuro--input-mode 'char)
       (kuro--apply-input-mode)
       (should update-called)))))

;;; Group 18 — kuro--input-mode-cycle-table + kuro-cycle-input-mode coverage gaps

(ert-deftest kuro-input-mode-test-cycle-is-interactive ()
  "`kuro-cycle-input-mode' is an interactive command."
  (should (commandp #'kuro-cycle-input-mode)))

(ert-deftest kuro-input-mode-test-cycle-errors-outside-kuro ()
  "`kuro-cycle-input-mode' signals user-error when not in a kuro buffer."
  (with-temp-buffer
    (should-error (kuro-cycle-input-mode) :type 'user-error)))

(ert-deftest kuro-input-mode-test-cycle-unknown-falls-back-to-semi-char ()
  "`kuro-cycle-input-mode' falls back to `kuro-semi-char-mode' for an unknown mode."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'nonexistent)
   (let (called)
     (cl-letf (((symbol-function 'kuro-semi-char-mode) (lambda () (setq called t))))
       (kuro-cycle-input-mode)
       (should called)))))

(ert-deftest kuro-input-mode-test-cycle-table-covers-all-modes ()
  "`kuro--input-mode-cycle-table' has entries for all three standard input modes."
  (should (assq 'semi-char kuro--input-mode-cycle-table))
  (should (assq 'char      kuro--input-mode-cycle-table))
  (should (assq 'line      kuro--input-mode-cycle-table)))

;;; Group 19 — kuro--input-mode-keymaps invariants

(ert-deftest kuro-input-mode-test-keymaps-has-char-entry ()
  "`kuro--input-mode-keymaps' has an entry for `char' mode."
  (should (assq 'char kuro--input-mode-keymaps)))

(ert-deftest kuro-input-mode-test-keymaps-has-semi-char-entry ()
  "`kuro--input-mode-keymaps' has an entry for `semi-char' mode."
  (should (assq 'semi-char kuro--input-mode-keymaps)))

(ert-deftest kuro-input-mode-test-keymaps-excludes-line ()
  "`kuro--input-mode-keymaps' has no entry for `line' mode (uses composed keymap)."
  (should-not (assq 'line kuro--input-mode-keymaps)))

(ert-deftest kuro-input-mode-test-keymaps-values-are-bound ()
  "Every value in `kuro--input-mode-keymaps' is a bound variable."
  (dolist (entry kuro--input-mode-keymaps)
    (should (boundp (cdr entry)))))


(provide 'kuro-input-mode-test-3)

;;; kuro-input-mode-test-3.el ends here
