;;; kuro-lifecycle-ext2-test-3.el --- Lifecycle tests (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-lifecycle-test-support)

;;; ── Group 34: kuro--read-attach-session-id ───────────────────────────────────

(ert-deftest kuro-lifecycle--read-attach-session-id-no-sessions ()
  "`kuro--read-attach-session-id' signals user-error when session list is nil."
  (cl-letf (((symbol-function 'kuro--list-sessions-safe) (lambda () nil)))
    (should-error (kuro--read-attach-session-id) :type 'user-error)))

(ert-deftest kuro-lifecycle--read-attach-session-id-no-detached ()
  "`kuro--read-attach-session-id' signals user-error when sessions exist but none detached."
  (cl-letf (((symbol-function 'kuro--list-sessions-safe)
             (lambda () '((1 "bash" nil t) (2 "fish" nil t)))))
    (should-error (kuro--read-attach-session-id) :type 'user-error)))

(ert-deftest kuro-lifecycle--read-attach-session-id-single-detached-returns-id ()
  "`kuro--read-attach-session-id' returns the session ID via completing-read."
  (cl-letf (((symbol-function 'kuro--list-sessions-safe)
             (lambda () '((42 "bash" t t))))
            ((symbol-function 'completing-read)
             (lambda (_prompt candidates &rest _)
               (caar candidates))))  ; select the first key
    (should (equal (kuro--read-attach-session-id) 42))))

(ert-deftest kuro-lifecycle--read-attach-session-id-picks-selected-candidate ()
  "`kuro--read-attach-session-id' returns the ID matching what completing-read chose."
  (cl-letf (((symbol-function 'kuro--list-sessions-safe)
             (lambda () '((7 "fish" t t) (99 "zsh" t t))))
            ((symbol-function 'completing-read)
             (lambda (_prompt candidates &rest _)
               ;; Simulate user picking the second candidate ("Session 99: zsh")
               (caadr candidates))))
    (should (equal (kuro--read-attach-session-id) 99))))

;;; ── Group 35: kuro--create-session-buffer ────────────────────────────────────

(ert-deftest kuro-lifecycle--create-session-buffer-default-name ()
  "`kuro--create-session-buffer' creates a live buffer when no name given."
  (cl-letf (((symbol-function 'kuro--show-buffer-if-interactive)
             (lambda (buf) buf)))
    (let ((buf (kuro--create-session-buffer)))
      (unwind-protect
          (should (buffer-live-p buf))
        (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--create-session-buffer-custom-name ()
  "`kuro--create-session-buffer' creates a buffer with the given name."
  (cl-letf (((symbol-function 'kuro--show-buffer-if-interactive)
             (lambda (buf) buf)))
    (let* ((name "*kuro-test-create-session-buf*")
           (buf (kuro--create-session-buffer name)))
      (unwind-protect
          (should (string= (buffer-name buf) name))
        (when (buffer-live-p buf) (kill-buffer buf))))))

(provide 'kuro-lifecycle-ext2-test-3)
;;; kuro-lifecycle-ext2-test-3.el ends here
