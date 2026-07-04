;;; kuro-lifecycle-ext2-test-5.el --- Lifecycle tests part 5 — Groups 35-36  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-lifecycle-test-support)


;;; ── Group 35: kuro--create-session-buffer (live-buffer check) ──

(ert-deftest kuro-lifecycle--create-session-buffer-returns-live-buffer ()
  "`kuro--create-session-buffer' always returns a live buffer."
  (let ((buf (kuro--create-session-buffer " *kuro-lifecycle-live-chk*")))
    (unwind-protect
        (should (buffer-live-p buf))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--create-session-buffer-idempotent-name ()
  "`kuro--create-session-buffer' returns an existing buffer if the name is already live."
  (let ((buf1 (kuro--create-session-buffer " *kuro-lifecycle-idem*")))
    (unwind-protect
        (let ((buf2 (kuro--create-session-buffer " *kuro-lifecycle-idem*")))
          (should (eq buf1 buf2)))
      (when (buffer-live-p buf1) (kill-buffer buf1)))))

(ert-deftest kuro-lifecycle--create-session-buffer-nil-name-returns-kuro-buffer ()
  "`kuro--create-session-buffer' with nil returns a buffer whose name contains \"kuro\"."
  (let ((buf (kuro--create-session-buffer nil)))
    (unwind-protect
        (should (string-match-p "kuro" (buffer-name buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))


;;; ── Group 36: kuro--attach-buffer ──

(ert-deftest kuro-lifecycle--attach-buffer-returns-live-buffer ()
  "`kuro--attach-buffer' returns a live buffer."
  (let ((buf (kuro--attach-buffer 42)))
    (unwind-protect
        (should (buffer-live-p buf))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--attach-buffer-name-contains-session-id ()
  "`kuro--attach-buffer' produces a buffer whose name embeds the session ID."
  (let ((buf (kuro--attach-buffer 17)))
    (unwind-protect
        (should (string-match-p "17" (buffer-name buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--attach-buffer-name-matches-session-buffer-name ()
  "`kuro--attach-buffer' uses `kuro--session-buffer-name' for naming."
  (let* ((expected (kuro--session-buffer-name 99))
         (buf      (kuro--attach-buffer 99)))
    (unwind-protect
        (should (string-match-p (regexp-quote (substring expected 1 -1))
                                (buffer-name buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--attach-buffer-each-call-fresh-buffer ()
  "`kuro--attach-buffer' called twice with same ID returns distinct buffers."
  (let ((buf1 (kuro--attach-buffer 7))
        (buf2 (kuro--attach-buffer 7)))
    (unwind-protect
        (should-not (eq buf1 buf2))
      (when (buffer-live-p buf1) (kill-buffer buf1))
      (when (buffer-live-p buf2) (kill-buffer buf2)))))


(provide 'kuro-lifecycle-ext2-test-5)
;;; kuro-lifecycle-ext2-test-5.el ends here
