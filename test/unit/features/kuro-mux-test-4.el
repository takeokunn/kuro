;;; kuro-mux-test-4.el --- kuro-mux ext2 coverage: layout, broadcast, clock  -*- lexical-binding: t; -*-

;;; Commentary:
;; Coverage for kuro-mux-ext2.el functions:
;;   - kuro-mux--parse-layout-plists (strict validator)
;;   - kuro-mux--session-spec (buffer-local -> typed session)
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

(defun kuro-mux-test-4--layout-session-field (session key)
  "Return typed layout SESSION field for KEY."
  (cond
   ((eq key :name) (kuro-mux--layout-session-name session))
   ((eq key :directory) (kuro-mux--layout-session-directory session))
   (t nil)))


;;; Group 30 — kuro-mux--parse-layout-plists

(ert-deftest kuro-mux-test--parse-layout-plists-empty ()
  "`kuro-mux--parse-layout-plists' returns nil for an empty list."
  (should (null (kuro-mux--parse-layout-plists nil))))

(ert-deftest kuro-mux-test--parse-layout-plists-valid-entry ()
  "`kuro-mux--parse-layout-plists' keeps strictly typed session specs."
  (let ((specs (list `(:name "work" :directory ,temporary-file-directory))))
    (let ((result (kuro-mux--parse-layout-plists specs)))
      (should (= 1 (length result)))
      (should (kuro-mux--layout-session-p (car result)))
      (should (equal "work" (kuro-mux-test-4--layout-session-field
                             (car result) :name)))
      (should (equal (file-name-as-directory temporary-file-directory)
                     (kuro-mux-test-4--layout-session-field
                      (car result) :directory)))
      (should-not (kuro-mux-test-4--layout-session-field
                   (car result) :command)))))

(ert-deftest kuro-mux-test--parse-layout-plists-rejects-invalid ()
  "`kuro-mux--parse-layout-plists' rejects malformed or weakly typed specs."
  (let ((specs (list '(:directory "/tmp")
                     '(:name "" :directory "/tmp")
                     '(:name "bad-cmd" :command "bash")
                     '(:name 42 :directory "/tmp")
                     `(:name "bad-dir"
                       :directory ,(expand-file-name "missing-kuro-dir" temporary-file-directory))
                     '(:name "ok" :directory "/tmp"))))
    (let ((result (kuro-mux--parse-layout-plists specs)))
      (should (null result)))))

(ert-deftest kuro-mux-test--parse-layout-plists-all-invalid ()
  "`kuro-mux--parse-layout-plists' returns nil when all entries are invalid."
  (let ((specs (list '(:directory "/")
                     '(:name "")
                     '(:name "bad" :command "bash")
                     '(:name "bad" :directory 99)
                     "not-a-list")))
    (should (null (kuro-mux--parse-layout-plists specs)))))

(ert-deftest kuro-mux-test--parse-layout-plists-multiple-valid ()
  "`kuro-mux--parse-layout-plists' keeps all valid entries in order."
  (let ((specs (list '(:name "s1" :directory "/tmp")
                     '(:name "s2" :directory "/tmp"))))
    (let ((result (kuro-mux--parse-layout-plists specs)))
      (should (= 2 (length result)))
      (should (kuro-mux--layout-session-p (nth 0 result)))
      (should (kuro-mux--layout-session-p (nth 1 result)))
      (should (equal "s1" (kuro-mux-test-4--layout-session-field
                           (nth 0 result) :name)))
      (should (equal (file-name-as-directory "/tmp")
                     (kuro-mux-test-4--layout-session-field
                      (nth 0 result) :directory)))
      (should (equal "s2" (kuro-mux-test-4--layout-session-field
                           (nth 1 result) :name)))
      (should (equal (file-name-as-directory "/tmp")
                     (kuro-mux-test-4--layout-session-field
                      (nth 1 result) :directory))))))


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
            (setq-local kuro-mux--directory "/tmp")
            (setq-local kuro-shell "sh")
            (let ((spec (kuro-mux--session-spec buf)))
              (should (kuro-mux--layout-session-p spec))
              (should (equal "my-session"
                             (kuro-mux-test-4--layout-session-field spec :name)))
              (should (equal (file-name-as-directory "/tmp")
                             (kuro-mux-test-4--layout-session-field
                              spec :directory)))
              (should-not (kuro-mux-test-4--layout-session-field spec :command))))
      (kill-buffer buf))))

(ert-deftest kuro-mux-test--session-spec-falls-back-to-buffer-name ()
  "`kuro-mux--session-spec' uses buffer-name when kuro-mux--name is nil."
  (let ((buf (generate-new-buffer "*test-spec-fallback*")))
    (unwind-protect
        (with-current-buffer buf
          (setq-local kuro-mux--name nil)
            (setq-local kuro-mux--directory "/home")
            (setq-local kuro-shell "sh")
            (let ((spec (kuro-mux--session-spec buf)))
              (should (kuro-mux--layout-session-p spec))
              (should (equal (buffer-name buf)
                             (kuro-mux-test-4--layout-session-field spec :name)))))
      (kill-buffer buf))))

(ert-deftest kuro-mux-test--session-spec-includes-directory ()
  "`kuro-mux--session-spec' includes :directory from buffer-local var."
  (let ((buf (generate-new-buffer "*test-spec-dir*"))
        (dir temporary-file-directory))
    (unwind-protect
        (with-current-buffer buf
          (setq-local kuro-mux--name nil)
            (setq-local kuro-mux--directory dir)
            (setq-local kuro-shell "sh")
            (let ((spec (kuro-mux--session-spec buf)))
              (should (kuro-mux--layout-session-p spec))
              (should (equal (file-name-as-directory dir)
                             (kuro-mux-test-4--layout-session-field
                              spec :directory)))))
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
            (insert "(kuro-mux-layout (:name \"s1\" :directory \"/tmp\"))"))
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
