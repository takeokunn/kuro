;;; kuro-mux-test-2.el --- ERT tests for kuro-mux.el — Groups 15-22  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

;;; Shared tables — commandp and prefix-map bindings

(defconst kuro-mux-test--commandp-table
  '((kuro-mux-test-clock-is-interactive          kuro-mux-clock)
    (kuro-mux-test-send-to-session-is-interactive kuro-mux-send-to-session)
    (kuro-mux-test-select-by-index-is-interactive kuro-mux-select-by-index)
    (kuro-mux-test-broadcast-toggle-is-interactive kuro-mux-broadcast-toggle)
    (kuro-mux-test-resize-pane-is-interactive     kuro-mux-resize-pane)
    (kuro-mux-test-swap-pane-forward-is-interactive kuro-mux-swap-pane-forward)
    (kuro-mux-test-swap-pane-backward-is-interactive kuro-mux-swap-pane-backward)
    (kuro-mux-test-other-window-is-interactive    kuro-mux-other-window)
    (kuro-mux-test-last-is-interactive            kuro-mux-last))
  "Table of (test-name fn-sym) for kuro-mux commandp assertions.")

(defmacro kuro-mux-test--def-commandp (test-name fn-sym)
  `(ert-deftest ,test-name ()
     ,(format "`%s' is an interactive command." fn-sym)
     (should (commandp #',fn-sym))))

(defconst kuro-mux-test--prefix-map-binding-table
  '((kuro-mux-test-clock-bound-in-prefix-map            "t" kuro-mux-clock)
    (kuro-mux-test-send-to-session-bound-in-prefix-map  "x" kuro-mux-send-to-session)
    (kuro-mux-test-broadcast-B-bound-in-prefix-map      "B" kuro-mux-broadcast-toggle)
    (kuro-mux-test-swap-forward-bound-in-prefix-map     "}" kuro-mux-swap-pane-forward)
    (kuro-mux-test-swap-backward-bound-in-prefix-map    "{" kuro-mux-swap-pane-backward)
    (kuro-mux-test-other-window-bound-in-prefix-map     "o" kuro-mux-other-window)
    (kuro-mux-test-last-bound-in-prefix-map             "L" kuro-mux-last))
  "Table of (test-name key-str fn-sym) for kuro-mux-prefix-map exact binding assertions.")

(defmacro kuro-mux-test--def-prefix-map-binding (test-name key-str fn-sym)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux-prefix-map' binds %S to `%s'." key-str fn-sym)
     (should (eq (lookup-key kuro-mux-prefix-map (kbd ,key-str)) #',fn-sym))))

;;; Group 15 — kuro-mux-detach / kuro-mux-zoom / kuro-mux-kill behaviour

(ert-deftest kuro-mux-test-detach-errors-outside-kuro-mode ()
  "`kuro-mux-detach' signals user-error when not in a kuro buffer."
  (with-temp-buffer
    (should-error (kuro-mux-detach) :type 'user-error)))

(ert-deftest kuro-mux-test-detach-deletes-window-when-multiple ()
  "`kuro-mux-detach' calls `delete-window' when more than one window exists."
  (let ((deleted nil))
    (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
              ((symbol-function 'count-windows)  (lambda () 2))
              ((symbol-function 'delete-window)  (lambda () (setq deleted t))))
      (kuro-mux-detach)
      (should deleted))))

(ert-deftest kuro-mux-test-detach-switches-session-when-single-window ()
  "`kuro-mux-detach' switches to the next session when only one window."
  (let ((switched nil))
    (cl-letf (((symbol-function 'derived-mode-p)      (lambda (&rest _) t))
              ((symbol-function 'count-windows)        (lambda () 1))
              ((symbol-function 'kuro-mux--live-sessions)
               (lambda () (list (current-buffer) (get-buffer-create "*other*"))))
              ((symbol-function 'kuro-mux-next)        (lambda () (setq switched t))))
      (kuro-mux-detach)
      (should switched))))

(ert-deftest kuro-mux-test-zoom-saves-config-on-first-call ()
  "`kuro-mux-zoom' sets `kuro-mux--zoom-config' on the first call."
  (let ((kuro-mux--zoom-config nil)
        (deleted nil))
    (cl-letf (((symbol-function 'current-window-configuration)
               (lambda () 'fake-config))
              ((symbol-function 'delete-other-windows)
               (lambda () (setq deleted t))))
      (kuro-mux-zoom)
      (should (eq kuro-mux--zoom-config 'fake-config))
      (should deleted))))

(ert-deftest kuro-mux-test-zoom-restores-config-on-second-call ()
  "`kuro-mux-zoom' restores the saved config and clears it on the second call."
  (let ((kuro-mux--zoom-config 'saved-config)
        (restored nil))
    (cl-letf (((symbol-function 'set-window-configuration)
               (lambda (cfg) (setq restored cfg))))
      (kuro-mux-zoom)
      (should (eq restored 'saved-config))
      (should (null kuro-mux--zoom-config)))))

(ert-deftest kuro-mux-test-kill-errors-outside-kuro-mode ()
  "`kuro-mux-kill' signals user-error when not in a kuro buffer."
  (with-temp-buffer
    (should-error (kuro-mux-kill) :type 'user-error)))

(ert-deftest kuro-mux-test-kill-without-confirm-kills-buffer ()
  "`kuro-mux-kill' kills the current buffer when confirm is nil."
  (let ((killed nil)
        (kuro-mux-kill-confirm nil))
    (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
              ((symbol-function 'kill-buffer)     (lambda (_) (setq killed t))))
      (kuro-mux-kill)
      (should killed))))

(ert-deftest kuro-mux-test-kill-confirm-defcustom-exists ()
  "`kuro-mux-kill-confirm' is a defined customization variable."
  (should (boundp 'kuro-mux-kill-confirm)))


;;; Group 16 — kuro-mux-clock

(kuro-mux-test--def-commandp         kuro-mux-test-clock-is-interactive   kuro-mux-clock)
(kuro-mux-test--def-prefix-map-binding kuro-mux-test-clock-bound-in-prefix-map "t" kuro-mux-clock)

;;; Group 17 — kuro-mux-send-to-session

(kuro-mux-test--def-commandp kuro-mux-test-send-to-session-is-interactive kuro-mux-send-to-session)

(ert-deftest kuro-mux-test-send-to-session-errors-on-unknown-name ()
  "`kuro-mux-send-to-session' signals user-error for an unknown session name."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil)))
    (should-error (kuro-mux-send-to-session "nonexistent" "hello")
                  :type 'user-error)))

(ert-deftest kuro-mux-test-send-to-session-calls-send-in-target-buffer ()
  "`kuro-mux-send-to-session' calls kuro--send-paste-or-raw in the target buffer."
  (let ((sent-text nil)
        (target-buf (generate-new-buffer "*kuro-mux-test-send-target*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list target-buf)))
                  ((symbol-function 'kuro-mux--session-display-name)
                   (lambda (buf) (buffer-name buf)))
                  ((symbol-function 'kuro--send-paste-or-raw)
                   (lambda (text) (setq sent-text text))))
          (kuro-mux-send-to-session "*kuro-mux-test-send-target*" "hello\n")
          (should (equal sent-text "hello\n")))
      (kill-buffer target-buf))))

(kuro-mux-test--def-prefix-map-binding kuro-mux-test-send-to-session-bound-in-prefix-map "x" kuro-mux-send-to-session)

;;; Group 18 — kuro-mux-select-by-index

(kuro-mux-test--def-commandp kuro-mux-test-select-by-index-is-interactive kuro-mux-select-by-index)

(defconst kuro-mux-test--select-by-index-table
  '((kuro-mux-test-select-by-index-switches-to-first-session  1)
    (kuro-mux-test-select-by-index-switches-to-second-session 2))
  "Table of (test-name idx) for `kuro-mux-select-by-index' session switching.")

(defmacro kuro-mux-test--def-select-by-index (test-name idx)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux-select-by-index' index %d switches to the %s session."
              idx (if (= idx 1) "first" "second"))
     (let ((buf-a (generate-new-buffer "*kuro-idx-test-a*"))
           (buf-b (generate-new-buffer "*kuro-idx-test-b*"))
           (switched-to nil))
       (unwind-protect
           (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                      (lambda () (list buf-a buf-b)))
                     ((symbol-function 'switch-to-buffer)
                      (lambda (buf) (setq switched-to buf))))
             (kuro-mux-select-by-index ,idx)
             ,(if (= idx 1)
                  `(should (eq switched-to buf-a))
                `(should (eq switched-to buf-b))))
         (kill-buffer buf-a)
         (kill-buffer buf-b)))))

(kuro-mux-test--def-select-by-index kuro-mux-test-select-by-index-switches-to-first-session  1)
(kuro-mux-test--def-select-by-index kuro-mux-test-select-by-index-switches-to-second-session 2)

(ert-deftest kuro-mux-test--all-select-by-index-correct ()
  "All entries in `kuro-mux-test--select-by-index-table' switch to the correct session."
  (dolist (entry kuro-mux-test--select-by-index-table)
    (pcase-let ((`(,_name ,idx) entry))
      (let ((buf-a (generate-new-buffer "*kuro-idx-inv-a*"))
            (buf-b (generate-new-buffer "*kuro-idx-inv-b*"))
            (switched-to nil))
        (unwind-protect
            (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                       (lambda () (list buf-a buf-b)))
                      ((symbol-function 'switch-to-buffer)
                       (lambda (buf) (setq switched-to buf))))
              (kuro-mux-select-by-index idx)
              (let ((expected (if (= idx 1) buf-a buf-b)))
                (should (eq switched-to expected))))
          (kill-buffer buf-a)
          (kill-buffer buf-b))))))

(ert-deftest kuro-mux-test-select-by-index-errors-when-out-of-range ()
  "`kuro-mux-select-by-index' signals user-error for an out-of-range index."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions)
             (lambda () (list (current-buffer)))))
    (should-error (kuro-mux-select-by-index 5) :type 'user-error)))

(defconst kuro-mux-test--select-index-key-table
  '((kuro-mux-test-select-by-index-1-bound "1")
    (kuro-mux-test-select-by-index-2-bound "2")
    (kuro-mux-test-select-by-index-3-bound "3")
    (kuro-mux-test-select-by-index-4-bound "4")
    (kuro-mux-test-select-by-index-5-bound "5")
    (kuro-mux-test-select-by-index-6-bound "6")
    (kuro-mux-test-select-by-index-7-bound "7")
    (kuro-mux-test-select-by-index-8-bound "8")
    (kuro-mux-test-select-by-index-9-bound "9"))
  "Table of (test-name key-str) verifying all 9 index keys are bound in `kuro-mux-prefix-map'.")

(defmacro kuro-mux-test--def-select-index-key (test-name key-str)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux-prefix-map' binds key %S to a command." key-str)
     (should (commandp (lookup-key kuro-mux-prefix-map (kbd ,key-str))))))

(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-1-bound "1")
(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-2-bound "2")
(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-3-bound "3")
(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-4-bound "4")
(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-5-bound "5")
(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-6-bound "6")
(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-7-bound "7")
(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-8-bound "8")
(kuro-mux-test--def-select-index-key kuro-mux-test-select-by-index-9-bound "9")

(ert-deftest kuro-mux-test-select-by-index--all-keys-bound ()
  "All 9 digit keys in `kuro-mux-prefix-map' map to commands."
  (dolist (entry kuro-mux-test--select-index-key-table)
    (pcase-let ((`(,_name ,key-str) entry))
      (should (commandp (lookup-key kuro-mux-prefix-map (kbd key-str)))))))

;;; Group 19 — kuro-mux-broadcast-mode

(kuro-mux-test--def-commandp kuro-mux-test-broadcast-toggle-is-interactive kuro-mux-broadcast-toggle)

(ert-deftest kuro-mux-test-broadcast-mode-off-by-default ()
  "`kuro-mux--broadcast-mode' defaults to nil."
  (should (null (default-value 'kuro-mux--broadcast-mode))))

(defconst kuro-mux-test--broadcast-toggle-table
  '((kuro-mux-test-broadcast-toggle-enables-mode  nil t)
    (kuro-mux-test-broadcast-toggle-disables-mode t   nil))
  "Table of (test-name init-val expectedp) for `kuro-mux-broadcast-toggle' state toggle.")

(defmacro kuro-mux-test--def-broadcast-toggle (test-name init-val expectedp)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux-broadcast-toggle' %s mode." (if expectedp "enables" "disables"))
     (let ((kuro-mux--broadcast-mode ,init-val))
       (kuro-mux-broadcast-toggle)
       ,(if expectedp `(should kuro-mux--broadcast-mode) `(should-not kuro-mux--broadcast-mode)))))

(kuro-mux-test--def-broadcast-toggle kuro-mux-test-broadcast-toggle-enables-mode  nil t)
(kuro-mux-test--def-broadcast-toggle kuro-mux-test-broadcast-toggle-disables-mode t   nil)

(ert-deftest kuro-mux-test--all-broadcast-toggles-correct ()
  "All entries in `kuro-mux-test--broadcast-toggle-table' toggle correctly."
  (dolist (entry kuro-mux-test--broadcast-toggle-table)
    (pcase-let ((`(,_name ,init-val ,expectedp) entry))
      (let ((kuro-mux--broadcast-mode init-val))
        (kuro-mux-broadcast-toggle)
        (if expectedp
            (should kuro-mux--broadcast-mode)
          (should-not kuro-mux--broadcast-mode))))))

(ert-deftest kuro-mux-test-broadcast-send-noop-when-mode-off ()
  "`kuro-mux--broadcast-send' does not call kuro--send-paste-or-raw when mode is off."
  (let ((kuro-mux--broadcast-mode nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-mux--live-sessions)
               (lambda () (list (current-buffer))))
              ((symbol-function 'kuro--send-paste-or-raw)
               (lambda (_) (setq called t))))
      (kuro-mux--broadcast-send "hello")
      (should-not called))))

(ert-deftest kuro-mux-test-broadcast-send-replicates-to-other-sessions ()
  "`kuro-mux--broadcast-send' sends text to all sessions except the origin buffer."
  (let* ((buf-b (generate-new-buffer "*kuro-bcast-test-b*"))
         (sent-to nil)
         (kuro-mux--broadcast-mode t)
         (kuro-mux--broadcasting nil))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list (current-buffer) buf-b)))
                  ((symbol-function 'kuro--send-paste-or-raw)
                   (lambda (text) (push (cons (current-buffer) text) sent-to))))
          (kuro-mux--broadcast-send "test-input")
          (should (= (length sent-to) 1))
          (should (eq (caar sent-to) buf-b))
          (should (equal (cdar sent-to) "test-input")))
      (kill-buffer buf-b))))

(ert-deftest kuro-mux-test-broadcast-send-noop-when-already-broadcasting ()
  "`kuro-mux--broadcast-send' is a no-op when `kuro-mux--broadcasting' is already t.
This guards against infinite recursion from the :after advice re-entering itself."
  (let ((kuro-mux--broadcast-mode t)
        (kuro-mux--broadcasting t)
        (called nil))
    (cl-letf (((symbol-function 'kuro-mux--live-sessions)
               (lambda () (list (current-buffer))))
              ((symbol-function 'kuro--send-paste-or-raw)
               (lambda (_) (setq called t))))
      (kuro-mux--broadcast-send "recursive-input")
      (should-not called))))

(kuro-mux-test--def-prefix-map-binding kuro-mux-test-broadcast-B-bound-in-prefix-map "B" kuro-mux-broadcast-toggle)

(provide 'kuro-mux-test-2)

;;; kuro-mux-test-2.el ends here

