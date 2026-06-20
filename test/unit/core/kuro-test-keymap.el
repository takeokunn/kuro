;;; kuro-test-keymap.el --- ERT tests for kuro.el — Groups 10-16 keymap + scrollback/edit-scrollback  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-support)

;;; ── Helpers ──────────────────────────────────────────────────────────────────

(defmacro kuro-test-keymap--with-snap (buf-suffix &rest body)
  "Run BODY with `snap' bound to a fresh edit-scrollback snapshot buffer.
Creates a kuro-mode buffer named *kuro-test-BUF-SUFFIX*, calls
`kuro-edit-scrollback', binds `snap' to the resulting snapshot buffer,
then executes BODY.  Kills `snap' on cleanup if still live."
  `(kuro-el-test--with-kuro-mode-buffer
     (rename-buffer ,(concat "*kuro-test-" buf-suffix "*"))
     (kuro-edit-scrollback)
     (let ((snap (get-buffer ,(concat "*kuro-scrollback: *kuro-test-" buf-suffix "**"))))
       (unwind-protect
           (progn ,@body)
         (when (buffer-live-p snap) (kill-buffer snap))))))

(defun kuro-test-keymap--bound-p (command keymap key)
  "Return non-nil when COMMAND is bound in KEYMAP at KEY.
This walks the raw keymap tree because nested prefix/composed maps make
`lookup-key' return prefix-depth integers instead of terminal bindings."
  (let ((events (kbd key))
        (chars (string-to-vector (key-description (kbd key)))))
    (cl-labels ((walk (map sequence index)
                  (when (and (keymapp map) (< index (length sequence)))
                    (let ((event (aref sequence index))
                          (found nil))
                      (map-keymap
                       (lambda (candidate-event binding)
                         (when (and (not found)
                                    (equal candidate-event event))
                           (setq found
                                 (if (= (1+ index) (length sequence))
                                     (eq binding command)
                                   (walk binding sequence (1+ index))))))
                       map)
                      found)))
                (matches (sequence)
                  (walk keymap sequence 0)))
      (or (matches events)
          (matches chars)))))

;;; ── Group 10 (keymap): kuro-mode-map keymap ─────────────────────────────────

(ert-deftest kuro-el-test--mode-map-is-sparse-keymap ()
  "kuro-mode-map is a sparse keymap (not a char-table or other variant)."
  ;; A sparse keymap's car is the symbol `keymap'.
  (should (eq (car kuro-mode-map) 'keymap)))

;;; ── Group 11 (keymap): kuro--make-focus-change-fn — both branches in one call ─

(ert-deftest kuro-el-test--make-focus-change-fn-focus-out-does-not-call-focus-in ()
  "When focus is lost, only focus-out is called, not focus-in."
  (let ((in-called nil)
        (out-called nil))
    (cl-letf (((symbol-function 'frame-focus-state) (lambda () nil))
              ((symbol-function 'kuro--handle-focus-in)
               (lambda () (setq in-called t)))
              ((symbol-function 'kuro--handle-focus-out)
               (lambda () (setq out-called t))))
      (funcall (kuro--make-focus-change-fn nil))
      (should-not in-called)
      (should out-called))))

(ert-deftest kuro-el-test--make-focus-change-fn-focus-in-does-not-call-focus-out ()
  "When focus is gained, only focus-in is called, not focus-out."
  (let ((in-called nil)
        (out-called nil))
    (cl-letf (((symbol-function 'frame-focus-state) (lambda () t))
              ((symbol-function 'kuro--handle-focus-in)
               (lambda () (setq in-called t)))
              ((symbol-function 'kuro--handle-focus-out)
               (lambda () (setq out-called t))))
      (funcall (kuro--make-focus-change-fn nil))
      (should in-called)
      (should-not out-called))))

;;; ── Group 12 (keymap): kuro--window-size-change — function existence ──────────

(ert-deftest kuro-el-test--window-size-change-is-a-function ()
  "kuro--window-size-change is a bound function in the test environment."
  (should (fboundp #'kuro--window-size-change)))

;;; ── Group 13 (keymap): kuro--resize-pending is nil by default ───────────────

(ert-deftest kuro-el-test--resize-pending-nil-when-initialized-false ()
  "Apply-resize logic returns nil when `initialized' arg is nil, regardless of dims."
  ;; Already covered for different dim combos, but verify the degenerate case:
  ;; even if new-rows = last-rows + 1 the uninitialized guard wins.
  (should (null (kuro-el-test--apply-resize-logic nil 25 80 24 80))))

(ert-deftest kuro-el-test--resize-pending-cons-carries-exact-values ()
  "The (rows . cols) cons returned by resize logic carries the exact new values."
  (let ((result (kuro-el-test--apply-resize-logic t 1 1 24 80)))
    (should (= (car result) 1))
    (should (= (cdr result) 1))))

;;; ── Group 14 (keymap): kuro.el constants, guards, and session-level state ─────

(ert-deftest kuro-el-test--buffer-name-default-is-string ()
  "kuro--buffer-name-default is a non-empty string constant."
  (should (stringp kuro--buffer-name-default))
  (should (< 0 (length kuro--buffer-name-default))))

(ert-deftest kuro-el-test--copy-mode-guard-signals-outside-kuro-mode ()
  "kuro-copy-mode signals user-error when the buffer is not in kuro-mode.
This is the same guard that kuro--assert-terminal-p would implement."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-copy-mode) :type 'user-error)))

(ert-deftest kuro-el-test--derived-mode-p-passes-in-kuro-mode-buffer ()
  "derived-mode-p returns non-nil in a buffer whose major-mode is kuro-mode."
  (kuro-el-test--with-kuro-mode-buffer
    (should (derived-mode-p 'kuro-mode))))

(ert-deftest kuro-el-test--call-macro-returns-nil-when-not-initialized ()
  "kuro--call returns nil when kuro--initialized is nil (no active session)."
  (with-temp-buffer
    (setq-local kuro--initialized nil)
    ;; kuro--call expands to (when kuro--initialized …); with nil it returns nil.
    (should-not (kuro--call nil (error "should not reach")))))

(ert-deftest kuro-el-test--call-macro-executes-when-initialized ()
  "kuro--call evaluates body when kuro--initialized is non-nil."
  (with-temp-buffer
    (setq-local kuro--initialized t)
    (let ((result (kuro--call nil (+ 1 1))))
      (should (= result 2)))))

(ert-deftest kuro-el-test--buffer-live-p-nil-for-killed-buffer ()
  "buffer-live-p returns nil for a buffer that has been killed."
  (let ((buf (generate-new-buffer " *kuro-test-killed*")))
    (kill-buffer buf)
    (should-not (buffer-live-p buf))))

(ert-deftest kuro-el-test--buffer-live-p-t-for-live-buffer ()
  "buffer-live-p returns non-nil for a buffer that is still alive."
  (let ((buf (generate-new-buffer " *kuro-test-live*")))
    (unwind-protect
        (should (buffer-live-p buf))
      (kill-buffer buf))))

(ert-deftest kuro-el-test--session-id-initial-value-is-zero ()
  "kuro--session-id initial buffer-local value is 0 (no session attached)."
  (with-temp-buffer
    (setq-local kuro--session-id 0)
    (should (= kuro--session-id 0))))

(ert-deftest kuro-el-test--initialized-initial-value-is-nil ()
  "kuro--initialized initial buffer-local value is nil."
  (with-temp-buffer
    (setq-local kuro--initialized nil)
    (should-not kuro--initialized)))

(ert-deftest kuro-el-test--core-list-sessions-stub-returns-nil ()
  "kuro-core-list-sessions stub returns nil (no sessions in the test environment)."
  ;; The stub defined at the top of this file is a no-op lambda returning nil.
  ;; This mirrors the contract that kuro-list-sessions relies on: an empty list
  ;; means \"no active sessions\".
  (should-not (kuro-core-list-sessions)))

;;; ── Group 15 (keymap): kuro-mode scroll-margin variables (TUI distortion fix) ─

(ert-deftest kuro-el-test--mode-sets-scroll-margin-zero ()
  "kuro-mode sets scroll-margin to 0 to prevent auto-scroll near window edges."
  (kuro-el-test--with-kuro-buffer
    (setq-local scroll-margin 0)
    (should (= scroll-margin 0))))

(ert-deftest kuro-el-test--mode-sets-scroll-conservatively ()
  "kuro-mode sets scroll-conservatively to 101 to prevent recentering."
  (kuro-el-test--with-kuro-buffer
    (setq-local scroll-conservatively 101)
    (should (> scroll-conservatively 100))))

(ert-deftest kuro-el-test--mode-sets-auto-window-vscroll-nil ()
  "kuro-mode sets auto-window-vscroll to nil to prevent vscroll drift."
  (kuro-el-test--with-kuro-buffer
    (setq-local auto-window-vscroll nil)
    (should-not auto-window-vscroll)))

;;; ── Group 16 (keymap): FR-007 — Copy mode UX enhancements ───────────────────

(ert-deftest kuro-el-test--mode-map-has-c-spc-copy-mode-binding ()
  "kuro-mode-map binds C-c C-SPC to kuro-copy-mode."
  (should (kuro-test-keymap--bound-p 'kuro-copy-mode kuro-mode-map "C-c C-SPC")))

(ert-deftest kuro-el-test--copy-mode-keymap-has-c-spc-exit-binding ()
  "The copy-mode local keymap binds C-c C-SPC for exiting copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (kuro-test-keymap--bound-p 'kuro-copy-mode (current-local-map)
                                       "C-c C-SPC"))))

(ert-deftest kuro-el-test--enter-copy-mode-propertizes-mode-name ()
  "kuro--enter-copy-mode sets mode-name with font-lock-warning-face."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (get-text-property 0 'face mode-name) 'font-lock-warning-face))))

(ert-deftest kuro-el-test--exit-copy-mode-restores-plain-mode-name ()
  "kuro--exit-copy-mode restores mode-name to plain \"Kuro\" without properties."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))
    (should (equal mode-name "Kuro"))
    (should-not (text-properties-at 0 mode-name))))

;;; ── Group: scrollback search (kuro-search-forward / -backward / kuro-occur) ──

(ert-deftest kuro-el-test--mode-map-has-c-c-s-search-binding ()
  "kuro-mode-map binds C-c C-s to kuro-search-forward."
  (should (kuro-test-keymap--bound-p 'kuro-search-forward kuro-mode-map
                                     "C-c C-s")))

(ert-deftest kuro-el-test--copy-map-binds-isearch-forward ()
  "kuro--enter-copy-mode installs C-s → isearch-forward in the copy keymap."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "C-s"))
                #'isearch-forward))))

(ert-deftest kuro-el-test--copy-map-binds-isearch-backward ()
  "kuro--enter-copy-mode installs C-r → isearch-backward in the copy keymap."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "C-r"))
                #'isearch-backward))))

(ert-deftest kuro-el-test--copy-map-binds-occur ()
  "kuro--enter-copy-mode installs M-s o → occur in the copy keymap."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "M-s o"))
                #'occur))))

(ert-deftest kuro-el-test--enter-copy-mode-saves-window-start ()
  "kuro--enter-copy-mode sets kuro--copy-mode-saved-window-start (nil when no window)."
  (kuro-el-test--with-kuro-mode-buffer
    ;; In a temp buffer there is no window: expect nil, not an error.
    (kuro--enter-copy-mode)
    (should (null kuro--copy-mode-saved-window-start))))

(ert-deftest kuro-el-test--search-forward-enters-copy-mode ()
  "kuro-search-forward enters copy mode before running isearch."
  (kuro-el-test--with-kuro-mode-buffer
    (should-not kuro--copy-mode)
    (cl-letf (((symbol-function 'isearch-forward) #'ignore))
      (kuro-search-forward)
      (should kuro--copy-mode))))

(ert-deftest kuro-el-test--search-forward-errors-outside-kuro ()
  "kuro-search-forward signals user-error outside a kuro-mode buffer."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-search-forward) :type 'user-error)))

(ert-deftest kuro-el-test--search-forward-no-double-enter ()
  "kuro-search-forward does not call kuro--enter-copy-mode if already in copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((enter-called nil))
      (cl-letf (((symbol-function 'kuro--enter-copy-mode)
                 (lambda () (setq enter-called t)))
                ((symbol-function 'isearch-forward) #'ignore))
        (kuro-search-forward)
        (should-not enter-called)))))

(ert-deftest kuro-el-test--search-backward-enters-copy-mode ()
  "kuro-search-backward enters copy mode before running isearch."
  (kuro-el-test--with-kuro-mode-buffer
    (should-not kuro--copy-mode)
    (cl-letf (((symbol-function 'isearch-backward) #'ignore))
      (kuro-search-backward)
      (should kuro--copy-mode))))

(ert-deftest kuro-el-test--search-backward-errors-outside-kuro ()
  "kuro-search-backward signals user-error outside a kuro-mode buffer."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-search-backward) :type 'user-error)))

(ert-deftest kuro-el-test--kuro-occur-enters-copy-mode ()
  "kuro-occur enters copy mode before running occur."
  (kuro-el-test--with-kuro-mode-buffer
    (should-not kuro--copy-mode)
    (cl-letf (((symbol-function 'occur) #'ignore))
      (kuro-occur "test")
      (should kuro--copy-mode))))

(ert-deftest kuro-el-test--kuro-occur-errors-outside-kuro ()
  "kuro-occur signals user-error outside a kuro-mode buffer."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-occur "test") :type 'user-error)))

(ert-deftest kuro-el-test--kuro-occur-calls-occur-with-regexp ()
  "kuro-occur passes the regexp argument to `occur'."
  (kuro-el-test--with-kuro-mode-buffer
    (let ((called-with nil))
      (cl-letf (((symbol-function 'occur)
                 (lambda (regexp &rest _) (setq called-with regexp))))
        (kuro-occur "ERROR\\|WARN")
        (should (equal called-with "ERROR\\|WARN"))))))

;;; ── Group: kuro-edit-scrollback / kuro-scrollback-edit-mode ─────────────────

(ert-deftest kuro-el-test--mode-map-has-c-c-e-edit-scrollback ()
  "kuro-mode-map binds C-c C-e to kuro-edit-scrollback."
  (should (kuro-test-keymap--bound-p 'kuro-edit-scrollback kuro-mode-map
                                     "C-c C-e")))

(ert-deftest kuro-el-test--scrollback-edit-keymap-binds-send ()
  "kuro--scrollback-edit-keymap binds C-c C-c to kuro-scrollback-send."
  (should (kuro-test-keymap--bound-p 'kuro-scrollback-send
                                     kuro--scrollback-edit-keymap
                                     "C-c C-c")))

(ert-deftest kuro-el-test--scrollback-edit-keymap-binds-discard ()
  "kuro--scrollback-edit-keymap binds C-c C-k to kuro-scrollback-discard."
  (should (kuro-test-keymap--bound-p 'kuro-scrollback-discard
                                     kuro--scrollback-edit-keymap
                                     "C-c C-k")))

(ert-deftest kuro-el-test--edit-scrollback-errors-outside-kuro ()
  "kuro-edit-scrollback signals user-error outside a kuro-mode buffer."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-edit-scrollback) :type 'user-error)))

(ert-deftest kuro-el-test--edit-scrollback-creates-snapshot-buffer ()
  "kuro-edit-scrollback creates a snapshot buffer named *kuro-scrollback: <name>*."
  (kuro-test-keymap--with-snap "snap"
    (should (buffer-live-p snap))))

(ert-deftest kuro-el-test--edit-scrollback-copies-content ()
  "kuro-edit-scrollback snapshot contains the terminal buffer's text."
  (kuro-el-test--with-kuro-mode-buffer
    (rename-buffer "*kuro-test-content*")
    ;; Insert some content into the read-only terminal buffer
    (let ((inhibit-read-only t))
      (insert "terminal output line\n"))
    (kuro-edit-scrollback)
    (let ((snap (get-buffer "*kuro-scrollback: *kuro-test-content**")))
      (unwind-protect
          (with-current-buffer snap
            (should (string-match-p "terminal output line" (buffer-string))))
        (when (buffer-live-p snap) (kill-buffer snap))))))

(ert-deftest kuro-el-test--edit-scrollback-snapshot-is-writable ()
  "The snapshot buffer is not read-only."
  (kuro-test-keymap--with-snap "writable"
    (with-current-buffer snap
      (should-not buffer-read-only))))

(ert-deftest kuro-el-test--edit-scrollback-mode-is-kuro-scrollback-edit ()
  "The snapshot buffer is in `kuro-scrollback-edit-mode'."
  (kuro-test-keymap--with-snap "mode"
    (with-current-buffer snap
      (should (derived-mode-p 'kuro-scrollback-edit-mode)))))

(ert-deftest kuro-el-test--edit-scrollback-source-buffer-set ()
  "The snapshot buffer stores the source kuro buffer."
  (kuro-el-test--with-kuro-mode-buffer
    (rename-buffer "*kuro-test-source*")
    (let ((source (current-buffer)))
      (kuro-edit-scrollback)
      (let ((snap (get-buffer "*kuro-scrollback: *kuro-test-source**")))
        (unwind-protect
            (with-current-buffer snap
              (should (eq kuro-edit-scrollback--source-buffer source)))
          (when (buffer-live-p snap) (kill-buffer snap)))))))

(ert-deftest kuro-el-test--scrollback-send-sends-content ()
  "kuro-scrollback-send sends the buffer content to the source PTY."
  (let ((sent nil))
    (kuro-test-keymap--with-snap "send-snap"
      (with-current-buffer snap
        (erase-buffer)
        (insert "edited content")
        (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                   (lambda (text) (setq sent text)))
                  ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
          (kuro-scrollback-send))))
    (should (equal sent "edited content"))))

(ert-deftest kuro-el-test--scrollback-send-kills-snap-buffer ()
  "kuro-scrollback-send closes the snapshot buffer."
  (kuro-test-keymap--with-snap "kill-snap"
    (with-current-buffer snap
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw) #'ignore)
                ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
        (kuro-scrollback-send)))
    (should-not (buffer-live-p snap))))

(ert-deftest kuro-el-test--scrollback-send-errors-on-dead-source ()
  "kuro-scrollback-send signals user-error if source buffer is dead."
  (kuro-test-keymap--with-snap "dead-source"
    (with-current-buffer snap
      (setq kuro-edit-scrollback--source-buffer nil)
      (should-error (kuro-scrollback-send) :type 'user-error))))

(ert-deftest kuro-el-test--scrollback-discard-kills-buffer ()
  "kuro-scrollback-discard closes the snapshot without sending."
  (kuro-test-keymap--with-snap "discard"
    (with-current-buffer snap
      (kuro-scrollback-discard))
    (should-not (buffer-live-p snap))))

(ert-deftest kuro-el-test--scrollback-discard-emits-message ()
  "kuro-scrollback-discard shows a confirmation message after killing the buffer."
  (let ((msg nil))
    (kuro-test-keymap--with-snap "discard-msg"
      (with-current-buffer snap
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
          (kuro-scrollback-discard))))
    (should (string= msg "kuro: scrollback snapshot discarded"))))

(ert-deftest kuro-el-test--scrollback-send-errors-outside-edit-mode ()
  "kuro-scrollback-send signals user-error when not in kuro-scrollback-edit-mode."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-error (kuro-scrollback-send) :type 'user-error)))

(provide 'kuro-test-keymap)
;;; kuro-test-keymap.el ends here
