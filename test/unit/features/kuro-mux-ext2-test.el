;;; kuro-mux-ext2-test.el --- Tests for kuro-mux-ext2.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)
(require 'kuro-mux-ext)
(require 'kuro-mux-ext2)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

(defmacro kuro-mux-ext2-test--with-buf (&rest body)
  "Run BODY in a fresh kuro-mode buffer, cleaned up on exit."
  `(let ((buf (generate-new-buffer " *kuro-ext2-test*")))
     (unwind-protect
         (with-current-buffer buf
           (kuro-mode)
           ,@body)
       (when (buffer-live-p buf) (kill-buffer buf)))))

(defmacro kuro-mux-ext2-test--with-layout-file (contents &rest body)
  "Run BODY with a temp layout file containing CONTENTS, cleaned up after."
  (declare (indent 1))
  `(let ((kuro-mux-layout-file (make-temp-file "kuro-layout-test-" nil ".el")))
     (unwind-protect
         (progn
           (when ,contents
             (with-temp-file kuro-mux-layout-file (insert ,contents)))
           ,@body)
       (when (file-exists-p kuro-mux-layout-file)
         (delete-file kuro-mux-layout-file)))))


;;; Group 65 — kuro-mux--session-spec

(ert-deftest kuro-mux-ext2-session-spec-dead-buffer-returns-nil ()
  "`kuro-mux--session-spec' returns nil for a dead buffer."
  (let ((dead (generate-new-buffer " *kuro-dead*")))
    (kill-buffer dead)
    (should (null (kuro-mux--session-spec dead)))))

(ert-deftest kuro-mux-ext2-session-spec-live-buffer ()
  "`kuro-mux--session-spec' returns a plist with :name, :command, :directory."
  (kuro-mux-ext2-test--with-buf
    (let ((kuro-mux--name "mysess")
          (kuro-mux--command "bash")
          (kuro-mux--directory "/tmp")
          (kuro-shell "sh"))
      (let ((spec (kuro-mux--session-spec (current-buffer))))
        (should (equal (plist-get spec :name) "mysess"))
        (should (equal (plist-get spec :command) "bash"))
        (should (equal (plist-get spec :directory) "/tmp"))))))

(ert-deftest kuro-mux-ext2-session-spec-falls-back-to-buffer-name ()
  "`kuro-mux--session-spec' uses `buffer-name' when `kuro-mux--name' is nil."
  (kuro-mux-ext2-test--with-buf
    (let ((kuro-mux--name nil)
          (kuro-mux--command nil)
          (kuro-mux--directory nil)
          (kuro-shell "zsh"))
      (let ((spec (kuro-mux--session-spec (current-buffer))))
        (should (equal (plist-get spec :name) (buffer-name)))
        (should (equal (plist-get spec :command) "zsh"))))))


;;; Group 66 — kuro-mux--parse-layout-plists

(ert-deftest kuro-mux-ext2-parse-layout-plists-keeps-valid ()
  "`kuro-mux--parse-layout-plists' keeps entries with :command."
  (let ((raw (list '(:name "s1" :command "bash" :directory "/tmp")
                   '(:name "s2" :command "zsh"  :directory "/home"))))
    (should (= (length (kuro-mux--parse-layout-plists raw)) 2))))

(ert-deftest kuro-mux-ext2-parse-layout-plists-drops-invalid ()
  "`kuro-mux--parse-layout-plists' silently drops entries without :command."
  (let ((raw (list '(:name "ok" :command "bash")
                   '(:name "bad")
                   "not-a-list")))
    (let ((result (kuro-mux--parse-layout-plists raw)))
      (should (= (length result) 1))
      (should (equal (plist-get (car result) :name) "ok")))))

(ert-deftest kuro-mux-ext2-parse-layout-plists-empty-input ()
  "`kuro-mux--parse-layout-plists' returns nil for empty input."
  (should (null (kuro-mux--parse-layout-plists nil))))


;;; Group 67 — kuro-mux--read-layout-file

(ert-deftest kuro-mux-ext2-read-layout-file-returns-nil-when-missing ()
  "`kuro-mux--read-layout-file' returns nil when the file does not exist."
  (let ((kuro-mux-layout-file "/tmp/no-such-kuro-layout-file-xyz.el"))
    (should (null (kuro-mux--read-layout-file)))))

(ert-deftest kuro-mux-ext2-read-layout-file-reads-valid-sexp ()
  "`kuro-mux--read-layout-file' returns the parsed sexp from the file."
  (kuro-mux-ext2-test--with-layout-file
      "(kuro-mux-layout (:name \"s1\" :command \"bash\" :directory \"/tmp\"))"
    (let ((result (kuro-mux--read-layout-file)))
      (should (eq (car result) 'kuro-mux-layout)))))

(ert-deftest kuro-mux-ext2-read-layout-file-returns-nil-on-parse-error ()
  "`kuro-mux--read-layout-file' returns nil when file content is not valid Lisp."
  (kuro-mux-ext2-test--with-layout-file
      "(this is ( broken"
    (should (null (kuro-mux--read-layout-file)))))


;;; Group 68 — kuro-mux-save-layout + kuro-mux-restore-layout

(ert-deftest kuro-mux-ext2-save-layout-is-interactive ()
  "`kuro-mux-save-layout' is an interactive command."
  (should (commandp #'kuro-mux-save-layout)))

(ert-deftest kuro-mux-ext2-save-layout-writes-file ()
  "`kuro-mux-save-layout' writes a file containing the kuro-mux-layout sexp."
  (kuro-mux-ext2-test--with-buf
    (let ((kuro-mux--name "s1")
          (kuro-mux--command "bash")
          (kuro-mux--directory "/tmp")
          (kuro-shell "sh")
          buf)
      (setq buf (current-buffer))
      (kuro-mux-ext2-test--with-layout-file nil
        (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () (list buf))))
          (kuro-mux-save-layout)
          (let ((content (with-temp-buffer
                           (insert-file-contents kuro-mux-layout-file)
                           (buffer-string))))
            (should (string-match-p "kuro-mux-layout" content))
            (should (string-match-p "bash" content))))))))

(ert-deftest kuro-mux-ext2-restore-layout-is-interactive ()
  "`kuro-mux-restore-layout' is an interactive command."
  (should (commandp #'kuro-mux-restore-layout)))

(ert-deftest kuro-mux-ext2-restore-layout-errors-when-no-file ()
  "`kuro-mux-restore-layout' signals user-error when layout file is missing."
  (let ((kuro-mux-layout-file "/tmp/no-such-kuro-layout-xyz.el"))
    (should-error (kuro-mux-restore-layout) :type 'user-error)))

(ert-deftest kuro-mux-ext2-restore-layout-errors-on-wrong-header ()
  "`kuro-mux-restore-layout' signals user-error when file header is wrong."
  (kuro-mux-ext2-test--with-layout-file
      "(wrong-header (:command \"bash\"))"
    (should-error (kuro-mux-restore-layout) :type 'user-error)))

(ert-deftest kuro-mux-ext2-restore-layout-calls-restore-session ()
  "`kuro-mux-restore-layout' calls `kuro-mux--restore-session' for each valid spec."
  (kuro-mux-ext2-test--with-layout-file
      "(kuro-mux-layout (:name \"s1\" :command \"bash\" :directory \"/tmp\"))"
    (let (restored-specs)
      (cl-letf (((symbol-function 'kuro-mux--restore-session)
                 (lambda (spec) (push spec restored-specs))))
        (kuro-mux-restore-layout)
        (should (= (length restored-specs) 1))
        (should (equal (plist-get (car restored-specs) :command) "bash"))))))


;;; Group 69 — kuro-mux-prefix-map + bindings tables

(ert-deftest kuro-mux-ext2-prefix-map-is-keymap ()
  "`kuro-mux-prefix-map' is a keymap."
  (should (keymapp kuro-mux-prefix-map)))

(ert-deftest kuro-mux-ext2-prefix-bindings-is-alist ()
  "`kuro-mux--prefix-bindings' is a non-empty alist."
  (should (listp kuro-mux--prefix-bindings))
  (should (> (length kuro-mux--prefix-bindings) 0))
  (should (consp (car kuro-mux--prefix-bindings))))

(ert-deftest kuro-mux-ext2-prefix-resize-bindings-covers-four-directions ()
  "`kuro-mux--prefix-resize-bindings' has entries for all four arrow keys."
  (let ((keys (mapcar #'car kuro-mux--prefix-resize-bindings)))
    (should (member "<up>"    keys))
    (should (member "<down>"  keys))
    (should (member "<left>"  keys))
    (should (member "<right>" keys))))


;;; Group 70 — kuro-mux-create + kuro-mux-install-keys

(ert-deftest kuro-mux-ext2-mux-create-is-interactive ()
  "`kuro-mux-create' is an interactive command."
  (should (commandp #'kuro-mux-create)))

(ert-deftest kuro-mux-ext2-mux-create-calls-kuro-create ()
  "`kuro-mux-create' passes COMMAND to `kuro-create'."
  (let (created-with)
    (cl-letf (((symbol-function 'kuro-create)
               (lambda (cmd) (setq created-with cmd))))
      (kuro-mux-create "fish")
      (should (equal created-with "fish")))))

(ert-deftest kuro-mux-ext2-install-keys-returns-keymap ()
  "`kuro-mux-install-keys' returns the keymap it bound into."
  (let ((map (make-sparse-keymap)))
    (should (eq (kuro-mux-install-keys map) map))))

(ert-deftest kuro-mux-ext2-install-keys-errors-on-no-keymap ()
  "`kuro-mux-install-keys' signals user-error when no valid keymap provided."
  (cl-letf (((symbol-function 'keymapp) (lambda (_) nil)))
    (should-error (kuro-mux-install-keys nil) :type 'user-error)))

(ert-deftest kuro-mux-ext2-install-keys-binds-in-keymap ()
  "`kuro-mux-install-keys' calls `define-key' with the prefix map."
  (let ((map (make-sparse-keymap)) bound-key)
    (cl-letf (((symbol-function 'define-key)
               (lambda (_m k v) (setq bound-key k))))
      (kuro-mux-install-keys map)
      (should bound-key))))


;;; Group 71 — kuro-mux-help + kuro-mux-clock

(ert-deftest kuro-mux-ext2-help-is-interactive ()
  "`kuro-mux-help' is an interactive command."
  (should (commandp #'kuro-mux-help)))

(ert-deftest kuro-mux-ext2-help-creates-buffer ()
  "`kuro-mux-help' creates a `*kuro-mux help*' buffer."
  (kuro-mux-help)
  (let ((buf (get-buffer "*kuro-mux help*")))
    (should (buffer-live-p buf))
    (when buf (kill-buffer buf))))

(ert-deftest kuro-mux-ext2-clock-is-interactive ()
  "`kuro-mux-clock' is an interactive command."
  (should (commandp #'kuro-mux-clock)))

(ert-deftest kuro-mux-ext2-clock-emits-time-message ()
  "`kuro-mux-clock' calls `message' with a time string."
  (let (msg)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
      (kuro-mux-clock)
      (should (string-match-p "kuro-mux:" (or msg "")))
      (should (string-match-p "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" (or msg ""))))))


;;; Group 72 — kuro-mux--broadcast-send + kuro-mux-broadcast-toggle

(ert-deftest kuro-mux-ext2-broadcast-toggle-is-interactive ()
  "`kuro-mux-broadcast-toggle' is an interactive command."
  (should (commandp #'kuro-mux-broadcast-toggle)))

(ert-deftest kuro-mux-ext2-broadcast-toggle-enables ()
  "`kuro-mux-broadcast-toggle' sets broadcast mode to t when currently nil."
  (let ((kuro-mux--broadcast-mode nil))
    (kuro-mux-broadcast-toggle)
    (should kuro-mux--broadcast-mode)
    (setq kuro-mux--broadcast-mode nil)))

(ert-deftest kuro-mux-ext2-broadcast-toggle-disables ()
  "`kuro-mux-broadcast-toggle' sets broadcast mode to nil when currently t."
  (let ((kuro-mux--broadcast-mode t))
    (kuro-mux-broadcast-toggle)
    (should-not kuro-mux--broadcast-mode)))

(ert-deftest kuro-mux-ext2-broadcast-send-noop-when-mode-off ()
  "`kuro-mux--broadcast-send' is a no-op when broadcast mode is off."
  (let ((kuro-mux--broadcast-mode nil)
        (kuro-mux--broadcasting nil)
        sent)
    (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () '(x)))
              ((symbol-function 'kuro--send-paste-or-raw) (lambda (_) (setq sent t))))
      (kuro-mux--broadcast-send "hi")
      (should-not sent))))

(ert-deftest kuro-mux-ext2-broadcast-send-replicates-to-other-bufs ()
  "`kuro-mux--broadcast-send' sends text to all sessions except origin."
  (let* ((origin (current-buffer))
         (target (generate-new-buffer " *kuro-broadcast-target*"))
         (kuro-mux--broadcast-mode t)
         (kuro-mux--broadcasting nil)
         sent-to)
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list origin target)))
                  ((symbol-function 'kuro--send-paste-or-raw)
                   (lambda (text) (push (current-buffer) sent-to))))
          (kuro-mux--broadcast-send "hello")
          (should (equal sent-to (list target))))
      (kill-buffer target))))

(ert-deftest kuro-mux-ext2-broadcast-send-re-entrancy-guard ()
  "`kuro-mux--broadcast-send' does not recurse when `kuro-mux--broadcasting' is set."
  (let ((kuro-mux--broadcast-mode t)
        (kuro-mux--broadcasting t)
        sent)
    (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () '(x)))
              ((symbol-function 'kuro--send-paste-or-raw) (lambda (_) (setq sent t))))
      (kuro-mux--broadcast-send "hi")
      (should-not sent))))


;;; Group 73 — kuro-mux-setup

(ert-deftest kuro-mux-ext2-setup-installs-hooks ()
  "`kuro-mux-setup' calls `kuro-mux--install-hooks'."
  (let ((kuro-mux-install-prefix-keys nil)
        (kuro-mux-mode-line-segment nil)
        hooks-installed)
    (cl-letf (((symbol-function 'kuro-mux--install-hooks)
               (lambda () (setq hooks-installed t))))
      (kuro-mux-setup)
      (should hooks-installed))))

(ert-deftest kuro-mux-ext2-setup-installs-keys-when-enabled ()
  "`kuro-mux-setup' calls `kuro-mux-install-keys' when `kuro-mux-install-prefix-keys' is t."
  (let ((kuro-mux-install-prefix-keys t)
        (kuro-mux-mode-line-segment nil)
        keys-installed)
    (cl-letf (((symbol-function 'kuro-mux--install-hooks) #'ignore)
              ((symbol-function 'boundp) (lambda (s) (if (eq s 'kuro-mode-map) t (boundp s))))
              ((symbol-function 'keymapp) (lambda (_) t))
              ((symbol-function 'kuro-mux-install-keys)
               (lambda (&optional _km) (setq keys-installed t))))
      (kuro-mux-setup)
      (should keys-installed))))


(provide 'kuro-mux-ext2-test)
;;; kuro-mux-ext2-test.el ends here
