;;; kuro-mux-test-4.el --- kuro-mux ext2 coverage: layout, broadcast, clock  -*- lexical-binding: t; -*-

;;; Commentary:
;; Coverage for kuro-mux-ext2.el functions:
;;   - kuro-mux--parse-layout-plists (pure filter)
;;   - kuro-mux--session-spec (buffer-local → plist)
;;   - kuro-mux--read-layout-file (file I/O)
;;   - kuro-mux-broadcast-toggle (state toggle)
;;   - kuro-mux-clock (message output)
;; Groups 30-32.

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))


;;; Group 30 — kuro-mux--parse-layout-plists

(ert-deftest kuro-mux-test--parse-layout-plists-empty ()
  "`kuro-mux--parse-layout-plists' returns nil for an empty list."
  (should (null (kuro-mux--parse-layout-plists nil))))

(ert-deftest kuro-mux-test--parse-layout-plists-valid-entry ()
  "`kuro-mux--parse-layout-plists' keeps plists that have :command."
  (let ((specs (list '(:command "fish" :name "work" :directory "/tmp"))))
    (let ((result (kuro-mux--parse-layout-plists specs)))
      (should (= 1 (length result)))
      (should (equal "fish" (plist-get (car result) :command))))))

(ert-deftest kuro-mux-test--parse-layout-plists-filters-invalid ()
  "`kuro-mux--parse-layout-plists' drops entries lacking :command."
  (let ((specs (list '(:name "no-cmd")
                     '(:command "zsh" :name "ok"))))
    (let ((result (kuro-mux--parse-layout-plists specs)))
      (should (= 1 (length result)))
      (should (equal "zsh" (plist-get (car result) :command))))))

(ert-deftest kuro-mux-test--parse-layout-plists-all-invalid ()
  "`kuro-mux--parse-layout-plists' returns nil when no entry has :command."
  (let ((specs (list '(:name "a") '(:directory "/") "not-a-list")))
    (should (null (kuro-mux--parse-layout-plists specs)))))

(ert-deftest kuro-mux-test--parse-layout-plists-multiple-valid ()
  "`kuro-mux--parse-layout-plists' keeps all valid entries in order."
  (let ((specs (list '(:command "bash" :name "s1")
                     '(:name "bad")
                     '(:command "zsh"  :name "s2"))))
    (let ((result (kuro-mux--parse-layout-plists specs)))
      (should (= 2 (length result)))
      (should (equal "bash" (plist-get (nth 0 result) :command)))
      (should (equal "zsh"  (plist-get (nth 1 result) :command))))))


;;; Group 31 — kuro-mux--session-spec

(ert-deftest kuro-mux-test--session-spec-dead-buffer-returns-nil ()
  "`kuro-mux--session-spec' returns nil for a dead buffer."
  (let ((dead-buf (generate-new-buffer "*test-dead*")))
    (kill-buffer dead-buf)
    (should (null (kuro-mux--session-spec dead-buf)))))

(ert-deftest kuro-mux-test--session-spec-uses-buffer-local-name ()
  "`kuro-mux--session-spec' uses kuro-mux--name when set."
  (let ((buf (generate-new-buffer "*test-spec-name*")))
    (unwind-protect
        (with-current-buffer buf
          (setq-local kuro-mux--name "my-session")
          (setq-local kuro-mux--command "fish")
          (setq-local kuro-mux--directory "/tmp")
          (setq-local kuro-shell "sh")
          (let ((spec (kuro-mux--session-spec buf)))
            (should (equal "my-session" (plist-get spec :name)))
            (should (equal "fish"       (plist-get spec :command)))))
      (kill-buffer buf))))

(ert-deftest kuro-mux-test--session-spec-falls-back-to-buffer-name ()
  "`kuro-mux--session-spec' uses buffer-name when kuro-mux--name is nil."
  (let ((buf (generate-new-buffer "*test-spec-fallback*")))
    (unwind-protect
        (with-current-buffer buf
          (setq-local kuro-mux--name nil)
          (setq-local kuro-mux--command "bash")
          (setq-local kuro-mux--directory "/home")
          (setq-local kuro-shell "sh")
          (let ((spec (kuro-mux--session-spec buf)))
            (should (equal (buffer-name buf) (plist-get spec :name)))))
      (kill-buffer buf))))

(ert-deftest kuro-mux-test--session-spec-includes-directory ()
  "`kuro-mux--session-spec' includes :directory from buffer-local var."
  (let ((buf (generate-new-buffer "*test-spec-dir*")))
    (unwind-protect
        (with-current-buffer buf
          (setq-local kuro-mux--name nil)
          (setq-local kuro-mux--command "fish")
          (setq-local kuro-mux--directory "/projects/kuro")
          (setq-local kuro-shell "sh")
          (let ((spec (kuro-mux--session-spec buf)))
            (should (equal "/projects/kuro" (plist-get spec :directory)))))
      (kill-buffer buf))))


;;; Group 32 — kuro-mux--read-layout-file / broadcast / clock

(ert-deftest kuro-mux-test--read-layout-file-nonexistent ()
  "`kuro-mux--read-layout-file' returns nil when the file does not exist."
  (let ((kuro-mux-layout-file "/tmp/kuro-nonexistent-layout-xyz.el"))
    (should (null (kuro-mux--read-layout-file)))))

(ert-deftest kuro-mux-test--read-layout-file-valid-sexp ()
  "`kuro-mux--read-layout-file' reads back a valid layout sexp from a temp file."
  (let* ((tmp (make-temp-file "kuro-layout-test" nil ".el"))
         (kuro-mux-layout-file tmp))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "(kuro-mux-layout (:command \"fish\" :name \"s1\"))"))
          (let ((result (kuro-mux--read-layout-file)))
            (should (eq 'kuro-mux-layout (car result)))))
      (delete-file tmp))))

(ert-deftest kuro-mux-test--read-layout-file-invalid-content ()
  "`kuro-mux--read-layout-file' returns nil when the file contains invalid Lisp."
  (let* ((tmp (make-temp-file "kuro-layout-bad" nil ".el"))
         (kuro-mux-layout-file tmp))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "((broken sexp"))
          (should (null (kuro-mux--read-layout-file))))
      (delete-file tmp))))

(ert-deftest kuro-mux-test--broadcast-toggle-turns-on ()
  "`kuro-mux-broadcast-toggle' enables broadcast mode from off state."
  (let ((kuro-mux--broadcast-mode nil))
    (kuro-mux-broadcast-toggle)
    (should kuro-mux--broadcast-mode)))

(ert-deftest kuro-mux-test--broadcast-toggle-turns-off ()
  "`kuro-mux-broadcast-toggle' disables broadcast mode from on state."
  (let ((kuro-mux--broadcast-mode t))
    (kuro-mux-broadcast-toggle)
    (should (null kuro-mux--broadcast-mode))))

(ert-deftest kuro-mux-test--broadcast-toggle-idempotent-off ()
  "`kuro-mux-broadcast-toggle' double-toggle restores original off state."
  (let ((kuro-mux--broadcast-mode nil))
    (kuro-mux-broadcast-toggle)
    (kuro-mux-broadcast-toggle)
    (should (null kuro-mux--broadcast-mode))))

(ert-deftest kuro-mux-test--clock-does-not-error ()
  "`kuro-mux-clock' runs without error and produces a non-empty message."
  (let (last-msg)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (setq last-msg (apply #'format fmt args)))))
      (kuro-mux-clock))
    (should (stringp last-msg))
    (should (string-prefix-p "kuro-mux: " last-msg))))


;;; Group 45 — kuro-mux-help behavioral coverage

(ert-deftest kuro-mux-test--help-creates-named-buffer ()
  "`kuro-mux-help' leaves a buffer named \"*kuro-mux help*\" in the buffer list."
  (cl-letf (((symbol-function 'substitute-command-keys) #'identity))
    (kuro-mux-help)
    (let ((buf (get-buffer "*kuro-mux help*")))
      (unwind-protect
          (should buf)
        (when buf (kill-buffer buf))))))

(ert-deftest kuro-mux-test--help-prints-prefix-key ()
  "`kuro-mux--help-insert' prints the current `kuro-mux-prefix-key'."
  (let ((kuro-mux-prefix-key "C-c x"))
    (let ((contents
           (with-temp-buffer
             (cl-letf (((symbol-function 'substitute-command-keys) #'identity))
               (kuro-mux--help-insert))
             (buffer-string))))
      (should (string-match-p "C-c x" contents)))))

(ert-deftest kuro-mux-test--help-prints-available-commands-header ()
  "`kuro-mux--help-insert' prints the \"Available commands\" section header."
  (let ((contents
         (with-temp-buffer
           (cl-letf (((symbol-function 'substitute-command-keys) #'identity))
             (kuro-mux--help-insert))
           (buffer-string))))
    (should (string-match-p "Available commands" contents))))

(ert-deftest kuro-mux-test--clock-message-contains-time ()
  "`kuro-mux-clock' message includes a time formatted as HH:MM:SS."
  (let (last-msg)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (setq last-msg (apply #'format fmt args))))
              ((symbol-function 'format-time-string)
               (lambda (_fmt) "12:34:56")))
      (kuro-mux-clock)
      (should (string-match-p "12:34:56" last-msg)))))


(provide 'kuro-mux-test-4)
;;; kuro-mux-test-4.el ends here
