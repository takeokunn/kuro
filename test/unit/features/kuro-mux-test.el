;;; kuro-mux-test.el --- Unit tests for kuro-mux.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the kuro-mux lightweight terminal multiplexer.
;; All tests use a mock kuro-mode (no Rust module) and mock kuro-create.

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

;; Minimal kuro-mode definition for tests
(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

;; Minimal kuro-create stub for tests that need it
(unless (fboundp 'kuro-create)
  (defun kuro-create (&optional command _buffer-name)
    (let ((buf (generate-new-buffer "*kuro-test*")))
      (with-current-buffer buf
        (kuro-mode)
        (setq kuro-mux--command command))
      (switch-to-buffer buf)
      buf)))

(defmacro kuro-mux-test--with-registry (&rest body)
  "Run BODY with a clean `kuro-mux--sessions' registry, restored on exit."
  `(let ((kuro-mux--sessions nil)
         (kuro-mux-tab-bar-mode nil))
     ,@body
     ;; Clean up any buffers created by kuro-create stubs
     (dolist (buf kuro-mux--sessions)
       (when (buffer-live-p buf)
         (kill-buffer buf)))
     (setq kuro-mux--sessions nil)))

(defmacro kuro-mux-test--make-session (name)
  "Create a mock kuro-mode buffer named NAME and register it.
Returns the buffer."
  `(let ((buf (get-buffer-create ,name)))
     (with-current-buffer buf
       (kuro-mode)
       (kuro-mux--register))
     buf))

(defmacro kuro-mux-test--check-spec (buf-name setup-form key expected)
  "In a registry, make session BUF-NAME, apply SETUP-FORM, check plist KEY equals EXPECTED."
  `(kuro-mux-test--with-registry
    (let ((buf (kuro-mux-test--make-session ,buf-name)))
      (with-current-buffer buf ,setup-form)
      (should (equal (plist-get (kuro-mux--session-spec buf) ,key) ,expected))
      (kill-buffer buf))))


;;; Group 1 — Registry management

(ert-deftest kuro-mux-test-register-adds-buffer ()
  "`kuro-mux--register' adds the current kuro buffer to the registry."
  (kuro-mux-test--with-registry
   (let ((buf (kuro-mux-test--make-session "*mux-r1*")))
     (should (memq buf kuro-mux--sessions))
     (kill-buffer buf))))

(ert-deftest kuro-mux-test-register-idempotent ()
  "`kuro-mux--register' does not add a buffer twice."
  (kuro-mux-test--with-registry
   (let ((buf (kuro-mux-test--make-session "*mux-r2*")))
     (with-current-buffer buf
       (kuro-mux--register))  ; second registration
     (should (= 1 (length (seq-filter (lambda (b) (eq b buf))
                                       kuro-mux--sessions))))
     (kill-buffer buf))))

(ert-deftest kuro-mux-test-register-preserves-order ()
  "Buffers are ordered by registration time (oldest first)."
  (kuro-mux-test--with-registry
   (let ((b1 (kuro-mux-test--make-session "*mux-o1*"))
         (b2 (kuro-mux-test--make-session "*mux-o2*"))
         (b3 (kuro-mux-test--make-session "*mux-o3*")))
     (should (equal kuro-mux--sessions (list b1 b2 b3)))
     (kill-buffer b1) (kill-buffer b2) (kill-buffer b3))))

(ert-deftest kuro-mux-test-unregister-removes-buffer ()
  "`kuro-mux--unregister' removes the current buffer from the registry."
  (kuro-mux-test--with-registry
   (let ((buf (kuro-mux-test--make-session "*mux-u1*")))
     (with-current-buffer buf (kuro-mux--unregister))
     (should-not (memq buf kuro-mux--sessions))
     (kill-buffer buf))))

(ert-deftest kuro-mux-test-unregister-noop-when-absent ()
  "`kuro-mux--unregister' is a no-op when buffer is not in registry."
  (kuro-mux-test--with-registry
   (let ((buf (get-buffer-create "*mux-u2*")))
     (with-current-buffer buf (kuro-mux--unregister))
     (should (null kuro-mux--sessions))
     (kill-buffer buf))))

(ert-deftest kuro-mux-test-live-sessions-prunes-dead-buffers ()
  "`kuro-mux--live-sessions' removes dead buffers from the registry."
  (kuro-mux-test--with-registry
   (let ((b1 (kuro-mux-test--make-session "*mux-l1*"))
         (b2 (kuro-mux-test--make-session "*mux-l2*")))
     (kill-buffer b1)
     (let ((live (kuro-mux--live-sessions)))
       (should-not (memq b1 live))
       (should (memq b2 live)))
     (kill-buffer b2))))


;;; Group 2 — Session display name

(ert-deftest kuro-mux-test-display-name-uses-mux-name ()
  "`kuro-mux--session-display-name' uses `kuro-mux--name' when set."
  (kuro-mux-test--with-registry
   (let ((buf (kuro-mux-test--make-session "*mux-n1*")))
     (with-current-buffer buf
       (setq kuro-mux--name "my-shell"))
     (should (string= (kuro-mux--session-display-name buf) "my-shell"))
     (kill-buffer buf))))

(ert-deftest kuro-mux-test-display-name-fallback-to-buffer-name ()
  "`kuro-mux--session-display-name' falls back to buffer name when no name set."
  (kuro-mux-test--with-registry
   (let ((buf (kuro-mux-test--make-session "*mux-n2*")))
     (should (string= (kuro-mux--session-display-name buf) "*mux-n2*"))
     (kill-buffer buf))))


;;; Group 3 — Navigation helpers

(ert-deftest kuro-mux-test-next-buffer-cycles ()
  "`kuro-mux--next-buffer' returns the buffer after the current one."
  (let* ((b1 (get-buffer-create "*mux-nav1*"))
         (b2 (get-buffer-create "*mux-nav2*"))
         (b3 (get-buffer-create "*mux-nav3*"))
         (sessions (list b1 b2 b3)))
    (should (eq (kuro-mux--next-buffer b1 sessions) b2))
    (should (eq (kuro-mux--next-buffer b2 sessions) b3))
    (should (eq (kuro-mux--next-buffer b3 sessions) b1))  ; wrap-around
    (kill-buffer b1) (kill-buffer b2) (kill-buffer b3)))

(ert-deftest kuro-mux-test-prev-buffer-cycles ()
  "`kuro-mux--prev-buffer' returns the buffer before the current one."
  (let* ((b1 (get-buffer-create "*mux-prev1*"))
         (b2 (get-buffer-create "*mux-prev2*"))
         (b3 (get-buffer-create "*mux-prev3*"))
         (sessions (list b1 b2 b3)))
    (should (eq (kuro-mux--prev-buffer b1 sessions) b3))  ; wrap-around
    (should (eq (kuro-mux--prev-buffer b2 sessions) b1))
    (should (eq (kuro-mux--prev-buffer b3 sessions) b2))
    (kill-buffer b1) (kill-buffer b2) (kill-buffer b3)))

(ert-deftest kuro-mux-test-next-buffer-single-session ()
  "`kuro-mux--next-buffer' with a single session returns itself (wrap)."
  (let* ((b1 (get-buffer-create "*mux-single*"))
         (sessions (list b1)))
    (should (eq (kuro-mux--next-buffer b1 sessions) b1))
    (kill-buffer b1)))

(ert-deftest kuro-mux-test-next-buffer-not-in-list ()
  "`kuro-mux--next-buffer' for a buffer not in the list returns the first."
  (let* ((b1 (get-buffer-create "*mux-ni1*"))
         (b2 (get-buffer-create "*mux-ni2*"))
         (bx (get-buffer-create "*mux-nix*"))
         (sessions (list b1 b2)))
    ;; memq returns nil → cdr of nil → (car nil) = nil → (car sessions) = b1
    (should (eq (kuro-mux--next-buffer bx sessions) b1))
    (kill-buffer b1) (kill-buffer b2) (kill-buffer bx)))


;;; Group 4 — kuro-mux-rename

(ert-deftest kuro-mux-test-rename-sets-mux-name ()
  "`kuro-mux-rename' sets `kuro-mux--name' in the current buffer."
  (kuro-mux-test--with-registry
   (let ((buf (kuro-mux-test--make-session "*mux-rn1*")))
     (with-current-buffer buf
       (kuro-mux-rename "my-session"))
     (should (string= (with-current-buffer buf kuro-mux--name)
                      "my-session"))
     (kill-buffer buf))))

(ert-deftest kuro-mux-test-rename-empty-string-clears-name ()
  "`kuro-mux-rename' with empty string clears the name (nil)."
  (kuro-mux-test--with-registry
   (let ((buf (kuro-mux-test--make-session "*mux-rn2*")))
     (with-current-buffer buf
       (setq kuro-mux--name "old-name")
       (kuro-mux-rename ""))
     (should (null (with-current-buffer buf kuro-mux--name)))
     (kill-buffer buf))))

(ert-deftest kuro-mux-test-rename-fails-outside-kuro ()
  "`kuro-mux-rename' signals `user-error' outside a kuro-mode buffer."
  (with-temp-buffer
    (should-error (kuro-mux-rename "foo") :type 'user-error)))

(ert-deftest kuro-mux-test-rename-updates-display-name ()
  "After `kuro-mux-rename', `kuro-mux--session-display-name' returns the new name."
  (kuro-mux-test--with-registry
   (let ((buf (kuro-mux-test--make-session "*mux-rn3*")))
     (with-current-buffer buf
       (kuro-mux-rename "new-name"))
     (should (string= (kuro-mux--session-display-name buf) "new-name"))
     (kill-buffer buf))))


;;; Group 5 — Mode-line lighter

(defconst kuro-mux-test--name-lighter-table
  '((kuro-mux-test-lighter-returns-name-in-braces "*mux-lt1*" "dev" " {dev}")
    (kuro-mux-test-lighter-empty-when-no-name     "*mux-lt2*" nil  ""))
  "Table of (test-name buf-name name-val expected) for `kuro-mux--name-lighter'.")

(defmacro kuro-mux-test--def-name-lighter (test-name buf-name name-val expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux--name-lighter': name=%S → %S." name-val expected)
     (kuro-mux-test--with-registry
       (let ((buf (kuro-mux-test--make-session ,buf-name)))
         (with-current-buffer buf
           (setq kuro-mux--name ,name-val)
           (should (string= (kuro-mux--name-lighter) ,expected)))
         (kill-buffer buf)))))

(kuro-mux-test--def-name-lighter kuro-mux-test-lighter-returns-name-in-braces "*mux-lt1*" "dev" " {dev}")
(kuro-mux-test--def-name-lighter kuro-mux-test-lighter-empty-when-no-name     "*mux-lt2*" nil  "")

(ert-deftest kuro-mux-test--all-name-lighter-cases-correct ()
  "Invariant: kuro-mux--name-lighter returns the expected string for each name-val."
  (dolist (entry kuro-mux-test--name-lighter-table)
    (pcase-let ((`(,_name ,buf-name ,name-val ,expected) entry))
      (kuro-mux-test--with-registry
        (let ((buf (kuro-mux-test--make-session buf-name)))
          (with-current-buffer buf
            (setq kuro-mux--name name-val)
            (should (string= (kuro-mux--name-lighter) expected)))
          (kill-buffer buf))))))


;;; Group 6 — Session spec for layout

(defconst kuro-mux-test--session-spec-table
  '((kuro-mux-test-session-spec-includes-name      "*mux-sp1*" kuro-mux--name      :name      "test-session")
    (kuro-mux-test-session-spec-includes-command   "*mux-sp2*" kuro-mux--command   :command   "fish")
    (kuro-mux-test-session-spec-includes-directory "*mux-sp3*" kuro-mux--directory :directory "/tmp"))
  "Table of (test-name buf-name var key expected) for `kuro-mux--session-spec' field assertions.")

(defmacro kuro-mux-test--def-session-spec (test-name buf-name var key expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux--session-spec' includes `%s' in the plist." key)
     (kuro-mux-test--check-spec ,buf-name (setq ,var ,expected) ,key ,expected)))

(kuro-mux-test--def-session-spec kuro-mux-test-session-spec-includes-name      "*mux-sp1*" kuro-mux--name      :name      "test-session")
(kuro-mux-test--def-session-spec kuro-mux-test-session-spec-includes-command   "*mux-sp2*" kuro-mux--command   :command   "fish")
(kuro-mux-test--def-session-spec kuro-mux-test-session-spec-includes-directory "*mux-sp3*" kuro-mux--directory :directory "/tmp")

(ert-deftest kuro-mux-test-session-spec-nil-for-dead-buffer ()
  "`kuro-mux--session-spec' returns nil for a dead buffer."
  (let ((buf (get-buffer-create "*mux-dead*")))
    (kill-buffer buf)
    (should (null (kuro-mux--session-spec buf)))))


;;; Group 7 — Layout file save/restore

(defmacro kuro-mux-test--with-layout-file (&rest body)
  "Run BODY with a temporary layout file, cleaned up on exit."
  `(let ((kuro-mux-layout-file (make-temp-file "kuro-mux-test-layout" nil ".el")))
     (unwind-protect
         (progn ,@body)
       (when (file-exists-p kuro-mux-layout-file)
         (delete-file kuro-mux-layout-file)))))

(ert-deftest kuro-mux-test-save-layout-creates-file ()
  "`kuro-mux-save-layout' creates the layout file."
  (kuro-mux-test--with-registry
   (kuro-mux-test--with-layout-file
    (let ((buf (kuro-mux-test--make-session "*mux-sl1*")))
      (with-current-buffer buf
        (setq kuro-mux--command "bash")
        (setq kuro-mux--directory "/tmp"))
      (kuro-mux-save-layout)
      (should (file-exists-p kuro-mux-layout-file))
      (kill-buffer buf)))))

(ert-deftest kuro-mux-test-save-layout-content-is-readable ()
  "`kuro-mux-save-layout' writes a readable sexp."
  (kuro-mux-test--with-registry
   (kuro-mux-test--with-layout-file
    (let ((buf (kuro-mux-test--make-session "*mux-sl2*")))
      (with-current-buffer buf
        (setq kuro-mux--name "dev")
        (setq kuro-mux--command "bash")
        (setq kuro-mux--directory "/home"))
      (kuro-mux-save-layout)
      (let ((layout (kuro-mux--read-layout-file)))
        (should (listp layout))
        (should (eq (car layout) 'kuro-mux-layout)))
      (kill-buffer buf)))))

(ert-deftest kuro-mux-test-read-layout-file-nil-when-absent ()
  "`kuro-mux--read-layout-file' returns nil when the file does not exist."
  (let ((kuro-mux-layout-file "/tmp/kuro-mux-nonexistent-test-99.el"))
    (should (null (kuro-mux--read-layout-file)))))

(ert-deftest kuro-mux-test-restore-layout-errors-without-file ()
  "`kuro-mux-restore-layout' signals user-error when layout file is absent."
  (let ((kuro-mux-layout-file "/tmp/kuro-mux-nonexistent-test-99.el"))
    (should-error (kuro-mux-restore-layout) :type 'user-error)))

(ert-deftest kuro-mux-test-save-restore-round-trip ()
  "Save a layout with two named sessions and restore it to recreate them."
  (kuro-mux-test--with-registry
   (kuro-mux-test--with-layout-file
    ;; Create two sessions
    (let ((b1 (kuro-mux-test--make-session "*mux-rt1*"))
          (b2 (kuro-mux-test--make-session "*mux-rt2*")))
      (with-current-buffer b1
        (setq kuro-mux--name "alpha"
              kuro-mux--command "bash"
              kuro-mux--directory "/tmp"))
      (with-current-buffer b2
        (setq kuro-mux--name "beta"
              kuro-mux--command "fish"
              kuro-mux--directory "/var"))
      (kuro-mux-save-layout)
      ;; Kill both sessions (simulate restart)
      (kill-buffer b1)
      (kill-buffer b2)
      (setq kuro-mux--sessions nil)
      ;; Now restore
      (cl-letf (((symbol-function 'kuro-create)
                 (lambda (cmd &rest _)
                   (let ((buf (generate-new-buffer (format "*kuro-rt-%s*" cmd))))
                     (with-current-buffer buf (kuro-mode))
                     (switch-to-buffer buf)
                     buf))))
        (kuro-mux-restore-layout)
        ;; Two new sessions should exist
        (should (= 2 (length (kuro-mux--live-sessions)))))
      ;; Clean up restored sessions
      (dolist (buf (kuro-mux--live-sessions)) (kill-buffer buf))))))


;;; Group 8 — Parse layout plists
;; The save format (written by pp) is a list of plist sublists:
;;   (kuro-mux-layout (:name "a" :command "sh" :directory "/a") (:name "b" ...))
;; `kuro-mux--parse-layout-plists' receives the cdr of that sexp.

(ert-deftest kuro-mux-test-parse-layout-plists-single ()
  "`kuro-mux--parse-layout-plists' parses a single session spec plist."
  (let* ((raw '((:name "dev" :command "bash" :directory "/tmp")))
         (parsed (kuro-mux--parse-layout-plists raw)))
    (should (= 1 (length parsed)))
    (should (string= (plist-get (car parsed) :name) "dev"))
    (should (string= (plist-get (car parsed) :command) "bash"))
    (should (string= (plist-get (car parsed) :directory) "/tmp"))))

(ert-deftest kuro-mux-test-parse-layout-plists-multiple ()
  "`kuro-mux--parse-layout-plists' parses multiple session spec plists."
  (let* ((raw '((:name "a" :command "sh" :directory "/a")
                (:name "b" :command "zsh" :directory "/b")))
         (parsed (kuro-mux--parse-layout-plists raw)))
    (should (= 2 (length parsed)))
    (should (string= (plist-get (nth 0 parsed) :name) "a"))
    (should (string= (plist-get (nth 1 parsed) :name) "b"))))

(ert-deftest kuro-mux-test-parse-layout-plists-empty ()
  "`kuro-mux--parse-layout-plists' returns nil for empty input."
  (should (null (kuro-mux--parse-layout-plists nil))))

(ert-deftest kuro-mux-test-parse-layout-plists-drops-invalid ()
  "`kuro-mux--parse-layout-plists' silently drops entries missing :command."
  (let* ((raw '((:name "ok" :command "bash") "not-a-list" (:name "broken")))
         (parsed (kuro-mux--parse-layout-plists raw)))
    (should (= 1 (length parsed)))
    (should (string= (plist-get (car parsed) :name) "ok"))))

(ert-deftest kuro-mux-test-restore-layout-errors-on-invalid-format ()
  "`kuro-mux-restore-layout' signals user-error when the layout file has an unexpected car."
  (kuro-mux-test--with-layout-file
    ;; Write a file with the wrong top-level tag.
    (let ((kuro-mux-layout-file (make-temp-file "kuro-mux-test-" nil ".el")))
      (unwind-protect
          (progn
            (with-temp-file kuro-mux-layout-file
              (insert "(wrong-tag (:name \"x\" :command \"sh\" :directory \"/\"))"))
            (should-error (kuro-mux-restore-layout) :type 'user-error))
        (when (file-exists-p kuro-mux-layout-file)
          (delete-file kuro-mux-layout-file))))))

(provide 'kuro-mux-test)
;;; kuro-mux-test.el ends here
