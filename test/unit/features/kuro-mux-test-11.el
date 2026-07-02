;;; kuro-mux-test-11.el --- ERT tests for kuro-mux.el — Groups 39-41  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

(defmacro kuro-mux-test--with-pipe-pane-dir (&rest body)
  "Run BODY with an isolated pipe-pane capture directory."
  (declare (indent 0) (debug t))
  `(let ((kuro-mux-pipe-pane-directory
          (make-temp-file "kuro-pipe-pane-test-" t)))
     (unwind-protect
         (progn ,@body)
       (when (file-directory-p kuro-mux-pipe-pane-directory)
         (delete-directory kuro-mux-pipe-pane-directory t)))))

(defun kuro-mux-test--pipe-pane-path (name)
  "Return NAME inside the isolated pipe-pane capture directory."
  (expand-file-name name
                    (file-name-as-directory
                     (file-truename kuro-mux-pipe-pane-directory))))

(defun kuro-mux-test--pipe-pane-target-path (target)
  "Return the path from pipe-pane TARGET."
  (should (kuro-mux--pipe-pane-target-p target))
  (kuro-mux--pipe-pane-target-path target))

(defun kuro-mux-test--read-file-string (file)
  "Return FILE contents as a string."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))


;;; Group 39 — kuro-mux-pipe-pane (start / stop / guard)

(ert-deftest kuro-mux-test-pipe-pane-rejects-non-kuro ()
  "`kuro-mux-pipe-pane' signals user-error outside kuro-mode."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (should-error (kuro-mux-pipe-pane "kuro-test.log") :type 'user-error))))

(ert-deftest kuro-mux-test-pipe-pane-starts-sets-file ()
  "`kuro-mux-pipe-pane' stores a canonical file inside the capture directory."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (kuro-mode)
      (unwind-protect
          (let ((expected (kuro-mux-test--pipe-pane-path "kuro-pipe-test.log")))
            (kuro-mux-pipe-pane "kuro-pipe-test.log")
            (should (equal (kuro-mux-test--pipe-pane-target-path
                            kuro-mux--pipe-pane-file)
                           expected))
            (should (file-regular-p expected)))
        (setq kuro-mux--pipe-pane-file nil)
        (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t)))))

(ert-deftest kuro-mux-test-pipe-pane-starts-with-absolute-direct-child ()
  "`kuro-mux-pipe-pane' accepts an absolute direct child of the capture directory."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (kuro-mode)
      (unwind-protect
          (let ((expected (kuro-mux-test--pipe-pane-path "absolute.log")))
            (kuro-mux-pipe-pane expected)
            (should (equal (kuro-mux-test--pipe-pane-target-path
                            kuro-mux--pipe-pane-file)
                           expected))
            (should (file-regular-p expected)))
        (setq kuro-mux--pipe-pane-file nil)
        (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t)))))

(ert-deftest kuro-mux-test-pipe-pane-starts-adds-watcher ()
  "`kuro-mux-pipe-pane' adds `kuro-mux--pipe-pane-watcher' to `after-change-functions'."
  (with-temp-buffer
    (kuro-mux-test--with-pipe-pane-dir
      (kuro-mode)
      (unwind-protect
          (progn
            (kuro-mux-pipe-pane "kuro-watcher-test.log")
            (should (memq #'kuro-mux--pipe-pane-watcher after-change-functions)))
        (setq kuro-mux--pipe-pane-file nil)
        (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t)))))

(ert-deftest kuro-mux-test-pipe-pane-stop-clears-file ()
  "`kuro-mux-pipe-pane' with nil stops piping (clears file)."
  (with-temp-buffer
    (kuro-mode)
    (setq kuro-mux--pipe-pane-file "old.log")
    (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
    (kuro-mux-pipe-pane nil)
    (should (null kuro-mux--pipe-pane-file))))

(ert-deftest kuro-mux-test-pipe-pane-stop-removes-watcher ()
  "`kuro-mux-pipe-pane' with nil removes the watcher hook."
  (with-temp-buffer
    (kuro-mode)
    (setq kuro-mux--pipe-pane-file "old-hook.log")
    (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
    (kuro-mux-pipe-pane nil)
    (should (null (memq #'kuro-mux--pipe-pane-watcher after-change-functions)))))

(ert-deftest kuro-mux-test-pipe-pane-is-interactive ()
  "`kuro-mux-pipe-pane' is an interactive command."
  (should (commandp #'kuro-mux-pipe-pane)))

(ert-deftest kuro-mux-test-pipe-pane-rejects-absolute-outside-directory ()
  "`kuro-mux-pipe-pane' rejects absolute paths outside the capture directory."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (kuro-mode)
      (should-error (kuro-mux-pipe-pane "/tmp/kuro-pipe-test.log")
                    :type 'user-error))))

(ert-deftest kuro-mux-test-pipe-pane-rejects-directory-traversal ()
  "`kuro-mux-pipe-pane' rejects traversal outside the capture directory."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (kuro-mode)
      (should-error (kuro-mux-pipe-pane "../escape.log")
                    :type 'user-error))))

(ert-deftest kuro-mux-test-pipe-pane-rejects-normalized-relative-path ()
  "`kuro-mux-pipe-pane' rejects relative paths that normalize to a safe basename."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (kuro-mode)
      (should-error (kuro-mux-pipe-pane "subdir/../normalized.log")
                    :type 'user-error))))

(ert-deftest kuro-mux-test-pipe-pane-rejects-unsafe-name ()
  "`kuro-mux-pipe-pane' rejects filenames outside the safe ASCII subset."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (kuro-mode)
      (should-error (kuro-mux-pipe-pane "bad name.log")
                    :type 'user-error))))

(ert-deftest kuro-mux-test-pipe-pane-rejects-symlink ()
  "`kuro-mux-pipe-pane' rejects symlink capture files."
  (kuro-mux-test--with-pipe-pane-dir
    (let* ((dir (kuro-mux--pipe-pane-safe-directory))
           (outside (make-temp-file "kuro-pipe-pane-outside-"))
           (link (expand-file-name "link.log" dir)))
      (unwind-protect
          (progn
            (make-symbolic-link outside link t)
            (with-temp-buffer
              (kuro-mode)
              (should-error (kuro-mux-pipe-pane "link.log")
                            :type 'user-error)))
        (when (file-exists-p link)
          (delete-file link))
        (when (file-exists-p outside)
          (delete-file outside))))))

(ert-deftest kuro-mux-test-pipe-pane-rejects-hardlink ()
  "`kuro-mux-pipe-pane' rejects hard-linked capture files."
  (kuro-mux-test--with-pipe-pane-dir
    (let* ((dir (kuro-mux--pipe-pane-safe-directory))
           (base (expand-file-name "base.log" dir))
           (link (expand-file-name "hard.log" dir)))
      (unwind-protect
          (progn
            (write-region "" nil base nil 'silent)
            (condition-case nil
                (add-name-to-file base link t)
              (file-error (ert-skip "hard links are not supported here")))
            (with-temp-buffer
              (kuro-mode)
              (should-error (kuro-mux-pipe-pane "hard.log")
                            :type 'user-error)))
        (when (file-exists-p link)
          (delete-file link))
        (when (file-exists-p base)
          (delete-file base))))))


;;; Group 40 — kuro-mux--pipe-pane-watcher (write, noop, error-recovery)

(ert-deftest kuro-mux-test-pipe-pane-watcher-noop-when-file-nil ()
  "`kuro-mux--pipe-pane-watcher' does nothing when `kuro-mux--pipe-pane-file' is nil."
  (with-temp-buffer
    (setq kuro-mux--pipe-pane-file nil)
    (insert "some text")
    (let ((written nil))
      (cl-letf (((symbol-function 'write-region)
                 (lambda (&rest _) (setq written t))))
        (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0)
        (should (null written))))))

(ert-deftest kuro-mux-test-pipe-pane-watcher-noop-when-beg-eq-end ()
  "`kuro-mux--pipe-pane-watcher' does nothing when BEG = END (no new text)."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (kuro-mode)
      (setq kuro-mux--pipe-pane-file
            (kuro-mux--pipe-pane-prepare-file "kuro-watcher-noop.log"))
      (let ((written nil))
        (cl-letf (((symbol-function 'write-region)
                   (lambda (&rest _) (setq written t))))
          (kuro-mux--pipe-pane-watcher 5 5 0)
          (should (null written))))
      (setq kuro-mux--pipe-pane-file nil))))

(ert-deftest kuro-mux-test-pipe-pane-watcher-appends-text ()
  "`kuro-mux--pipe-pane-watcher' calls `write-region' with the new text."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (insert "hello world")
      (setq kuro-mux--pipe-pane-file
            (kuro-mux--pipe-pane-prepare-file "kuro-append-test.log"))
      (let ((written-text nil)
            (written-file nil)
            (written-append nil))
        (cl-letf (((symbol-function 'write-region)
                   (lambda (text _ignored file append _silent)
                     (setq written-text text
                           written-file file
                           written-append append))))
          (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0)
          (should (equal written-text "hello world"))
          (should (equal written-file
                         (kuro-mux-test--pipe-pane-path "kuro-append-test.log")))
          (should (eq written-append t))))
      (setq kuro-mux--pipe-pane-file nil))))

(ert-deftest kuro-mux-test-pipe-pane-watcher-clears-file-on-error ()
  "`kuro-mux--pipe-pane-watcher' clears the file path and removes hook on write error."
  (kuro-mux-test--with-pipe-pane-dir
    (with-temp-buffer
      (insert "test")
      (setq kuro-mux--pipe-pane-file
            (kuro-mux--pipe-pane-prepare-file "kuro-error-test.log"))
      (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
      (cl-letf (((symbol-function 'write-region)
                 (lambda (&rest _) (error "write failed"))))
        (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0))
      (should (null kuro-mux--pipe-pane-file))
      (should (null (memq #'kuro-mux--pipe-pane-watcher after-change-functions))))))

(ert-deftest kuro-mux-test-pipe-pane-watcher-clears-file-on-symlink ()
  "`kuro-mux--pipe-pane-watcher' disables piping if the active file becomes a symlink."
  (kuro-mux-test--with-pipe-pane-dir
    (let* ((outside (make-temp-file "kuro-pipe-pane-outside-"))
           (target (kuro-mux--pipe-pane-prepare-file "swap.log"))
           (target-path (kuro-mux--pipe-pane-target-path target)))
      (unwind-protect
          (with-temp-buffer
            (insert "test")
            (delete-file target-path)
            (make-symbolic-link outside target-path t)
            (setq kuro-mux--pipe-pane-file target)
            (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
            (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0)
            (should (null kuro-mux--pipe-pane-file))
            (should (null (memq #'kuro-mux--pipe-pane-watcher
                                after-change-functions))))
        (when (or (file-exists-p target-path) (file-symlink-p target-path))
          (delete-file target-path))
        (when (file-exists-p outside)
          (delete-file outside))))))

(ert-deftest kuro-mux-test-pipe-pane-watcher-clears-file-on-delete ()
  "`kuro-mux--pipe-pane-watcher' disables piping if the active file disappears."
  (kuro-mux-test--with-pipe-pane-dir
    (let* ((target (kuro-mux--pipe-pane-prepare-file "deleted.log"))
           (target-path (kuro-mux--pipe-pane-target-path target)))
      (with-temp-buffer
        (insert "test")
        (delete-file target-path)
        (setq kuro-mux--pipe-pane-file target)
        (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
        (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0)
        (should (null kuro-mux--pipe-pane-file))
        (should (null (memq #'kuro-mux--pipe-pane-watcher
                            after-change-functions)))
        (should-not (file-exists-p target-path))))))

(ert-deftest kuro-mux-test-pipe-pane-watcher-clears-file-on-replacement ()
  "`kuro-mux--pipe-pane-watcher' disables piping if the active file is replaced."
  (kuro-mux-test--with-pipe-pane-dir
    (let* ((target (kuro-mux--pipe-pane-prepare-file "replaced.log"))
           (target-path (kuro-mux--pipe-pane-target-path target))
           (replacement (kuro-mux-test--pipe-pane-path "replacement.tmp")))
      (unwind-protect
          (progn
            (write-region "replacement" nil replacement nil 'silent)
            (set-file-modes replacement #o600)
            (delete-file target-path)
            (rename-file replacement target-path)
            (let* ((attributes (file-attributes target-path 'integer))
                   (device (file-attribute-device-number attributes))
                   (inode (file-attribute-inode-number attributes)))
              (when (and (= device (kuro-mux--pipe-pane-target-device target))
                         (= inode (kuro-mux--pipe-pane-target-inode target)))
                (ert-skip "filesystem reused device/inode for replacement")))
            (with-temp-buffer
              (insert "test")
              (setq kuro-mux--pipe-pane-file target)
              (add-hook 'after-change-functions
                        #'kuro-mux--pipe-pane-watcher nil t)
              (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0)
              (should (null kuro-mux--pipe-pane-file))
              (should (null (memq #'kuro-mux--pipe-pane-watcher
                                  after-change-functions)))
              (should (equal (kuro-mux-test--read-file-string target-path)
                             "replacement"))))
        (when (file-exists-p replacement)
          (delete-file replacement))))))

(ert-deftest kuro-mux-test-pipe-pane-watcher-clears-file-on-mode-drift ()
  "`kuro-mux--pipe-pane-watcher' disables piping if the active file mode drifts."
  (kuro-mux-test--with-pipe-pane-dir
    (let* ((target (kuro-mux--pipe-pane-prepare-file "mode-drift.log"))
           (target-path (kuro-mux--pipe-pane-target-path target)))
      (unwind-protect
          (with-temp-buffer
            (insert "test")
            (set-file-modes target-path #o644)
            (setq kuro-mux--pipe-pane-file target)
            (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
            (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0)
            (should (null kuro-mux--pipe-pane-file))
            (should (null (memq #'kuro-mux--pipe-pane-watcher
                                after-change-functions)))
            (should (equal (kuro-mux-test--read-file-string target-path) "")))
        (when (file-exists-p target-path)
          (set-file-modes target-path #o600))))))


;;; Group 41 — kuro-mux--on-session-created / kuro-mux--on-session-killed behavior

(ert-deftest kuro-mux-test-on-session-created-calls-register ()
  "`kuro-mux--on-session-created' registers the current buffer."
  (let ((kuro-mux--sessions nil)
        (kuro-mux-tab-bar-mode nil))
    (with-temp-buffer
      (kuro-mode)
      (kuro-mux--on-session-created)
      (should (memq (current-buffer) kuro-mux--sessions)))
    (setq kuro-mux--sessions nil)))

(ert-deftest kuro-mux-test-on-session-killed-calls-unregister ()
  "`kuro-mux--on-session-killed' removes the buffer from the registry."
  (let ((kuro-mux--sessions nil)
        (kuro-mux-tab-bar-mode nil))
    (let ((buf (get-buffer-create " *kuro-mux-kill-test*")))
      (unwind-protect
          (progn
            (with-current-buffer buf
              (kuro-mode)
              (kuro-mux--register))
            (should (memq buf kuro-mux--sessions))
            (with-current-buffer buf
              (kuro-mux--on-session-killed))
            (should-not (memq buf kuro-mux--sessions)))
        (when (buffer-live-p buf) (kill-buffer buf))
        (setq kuro-mux--sessions nil)))))

(ert-deftest kuro-mux-test-tab-bar-mode-is-a-minor-mode ()
  "`kuro-mux-tab-bar-mode' is a global minor mode."
  (should (commandp #'kuro-mux-tab-bar-mode)))

(ert-deftest kuro-mux-test-tab-bar-mode-enable-installs-hooks ()
  "Enabling `kuro-mux-tab-bar-mode' installs lifecycle hooks."
  (let ((kuro-mux-tab-bar-mode nil)
        (kuro-mode-hook nil)
        (kill-buffer-hook nil))
    (kuro-mux-tab-bar-mode 1)
    (unwind-protect
        (should (memq #'kuro-mux--on-session-created kuro-mode-hook))
      (kuro-mux-tab-bar-mode -1)
      (setq kuro-mode-hook nil kill-buffer-hook nil))))

(ert-deftest kuro-mux-test-tab-bar-mode-disable-uninstalls-hooks ()
  "Disabling `kuro-mux-tab-bar-mode' removes lifecycle hooks."
  (let ((kuro-mux-tab-bar-mode nil)
        (kuro-mode-hook nil)
        (kill-buffer-hook nil))
    (kuro-mux-tab-bar-mode 1)
    (kuro-mux-tab-bar-mode -1)
    (should-not (memq #'kuro-mux--on-session-created kuro-mode-hook))
    (setq kuro-mode-hook nil kill-buffer-hook nil)))


(provide 'kuro-mux-test-11)
;;; kuro-mux-test-11.el ends here
