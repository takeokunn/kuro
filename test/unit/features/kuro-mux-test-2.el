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

(kuro-mux-test--def-prefix-map-binding kuro-mux-test-broadcast-B-bound-in-prefix-map "B" kuro-mux-broadcast-toggle)

;;; Group 20 — kuro-mux-resize-pane + session index + mode-line segment

(kuro-mux-test--def-commandp kuro-mux-test-resize-pane-is-interactive kuro-mux-resize-pane)

(defconst kuro-mux-test--resize-pane-table
  '((kuro-mux-test-resize-pane-up-calls-enlarge-window                 up    enlarge-window                3)
    (kuro-mux-test-resize-pane-down-calls-shrink-window                down  shrink-window                 2)
    (kuro-mux-test-resize-pane-left-calls-shrink-window-horizontally   left  shrink-window-horizontally    5)
    (kuro-mux-test-resize-pane-right-calls-enlarge-window-horizontally right enlarge-window-horizontally   4))
  "Table of (test-name dir fn delta) for `kuro-mux-resize-pane' direction dispatch.")

(defmacro kuro-mux-test--def-resize-pane (test-name dir fn delta)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux-resize-pane' %s calls `%s' with the given delta." dir fn)
     (let ((called-n nil))
       (cl-letf (((symbol-function ',fn) (lambda (n) (setq called-n n))))
         (kuro-mux-resize-pane ',dir ,delta)
         (should (= called-n ,delta))))))

(kuro-mux-test--def-resize-pane kuro-mux-test-resize-pane-up-calls-enlarge-window                 up    enlarge-window                3)
(kuro-mux-test--def-resize-pane kuro-mux-test-resize-pane-down-calls-shrink-window                down  shrink-window                 2)
(kuro-mux-test--def-resize-pane kuro-mux-test-resize-pane-left-calls-shrink-window-horizontally   left  shrink-window-horizontally    5)
(kuro-mux-test--def-resize-pane kuro-mux-test-resize-pane-right-calls-enlarge-window-horizontally right enlarge-window-horizontally   4)

(ert-deftest kuro-mux-test--all-resize-pane-directions-correct ()
  "All entries in `kuro-mux-test--resize-pane-table' dispatch to the correct window fn."
  (dolist (entry kuro-mux-test--resize-pane-table)
    (pcase-let ((`(,_name ,dir ,fn ,delta) entry))
      (let ((called-n nil))
        (cl-letf (((symbol-function fn) (lambda (n) (setq called-n n))))
          (kuro-mux-resize-pane dir delta)
          (should (= called-n delta)))))))

(ert-deftest kuro-mux-test-resize-pane-errors-on-invalid-direction ()
  "`kuro-mux-resize-pane' signals user-error for an unknown direction."
  (should-error (kuro-mux-resize-pane 'diagonal 1) :type 'user-error))

(ert-deftest kuro-mux-test-resize-pane-arrow-up-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds <up> to a command (resize-pane lambda)."
  (should (commandp (lookup-key kuro-mux-prefix-map (kbd "<up>")))))

(ert-deftest kuro-mux-test-session-index-returns-position ()
  "`kuro-mux--session-index' returns 1-indexed position in the sessions list."
  (let ((buf-a (current-buffer))
        (buf-b (generate-new-buffer "*kuro-idx-seg-b*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list buf-a buf-b))))
          (should (= (kuro-mux--session-index) 1))
          (with-current-buffer buf-b
            (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                       (lambda () (list buf-a buf-b))))
              (should (= (kuro-mux--session-index) 2)))))
      (kill-buffer buf-b))))

(ert-deftest kuro-mux-test-session-index-nil-when-not-registered ()
  "`kuro-mux--session-index' returns nil when buffer is not in session list."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil)))
    (should (null (kuro-mux--session-index)))))

(ert-deftest kuro-mux-test-mode-line-segment-shows-index ()
  "`kuro-mux--mode-line-segment' returns \" [N/M]\" for a registered buffer."
  (let ((buf-a (current-buffer))
        (buf-b (generate-new-buffer "*kuro-ml-seg-b*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list buf-a buf-b))))
          (should (equal (kuro-mux--mode-line-segment) " [1/2]")))
      (kill-buffer buf-b))))

(ert-deftest kuro-mux-test-mode-line-segment-empty-when-not-registered ()
  "`kuro-mux--mode-line-segment' returns empty string when not registered."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil)))
    (should (equal (kuro-mux--mode-line-segment) ""))))

;;; Group 21 — kuro-mux-swap-pane + mode-line segment installation

(kuro-mux-test--def-commandp kuro-mux-test-swap-pane-forward-is-interactive  kuro-mux-swap-pane-forward)
(kuro-mux-test--def-commandp kuro-mux-test-swap-pane-backward-is-interactive kuro-mux-swap-pane-backward)

(defconst kuro-mux-test--swap-pane-error-table
  '((kuro-mux-test-swap-pane-forward-errors-single-window  kuro-mux-swap-pane-forward  next-window)
    (kuro-mux-test-swap-pane-backward-errors-single-window kuro-mux-swap-pane-backward previous-window))
  "Table of (test-name fn-sym nav-fn) for swap-pane single-window user-error cases.")

(defmacro kuro-mux-test--def-swap-pane-error (test-name fn-sym nav-fn)
  `(ert-deftest ,test-name ()
     ,(format "`%s' signals user-error when there is only one window." fn-sym)
     (cl-letf (((symbol-function ',nav-fn)
                (lambda (&rest _) (selected-window))))
       (should-error (,fn-sym) :type 'user-error))))

(kuro-mux-test--def-swap-pane-error kuro-mux-test-swap-pane-forward-errors-single-window  kuro-mux-swap-pane-forward  next-window)
(kuro-mux-test--def-swap-pane-error kuro-mux-test-swap-pane-backward-errors-single-window kuro-mux-swap-pane-backward previous-window)

(ert-deftest kuro-mux-test--all-swap-pane-error-single-window ()
  "Both swap-pane commands signal user-error when only one window is visible."
  (dolist (entry kuro-mux-test--swap-pane-error-table)
    (pcase-let ((`(,_name ,fn-sym ,nav-fn) entry))
      (cl-letf (((symbol-function nav-fn) (lambda (&rest _) (selected-window))))
        (should-error (funcall fn-sym) :type 'user-error)))))

(defconst kuro-mux-test--swap-pane-call-table
  '((kuro-mux-test-swap-pane-forward-calls-window-swap-states  kuro-mux-swap-pane-forward  next-window)
    (kuro-mux-test-swap-pane-backward-calls-window-swap-states kuro-mux-swap-pane-backward previous-window))
  "Table of (test-name fn-sym nav-fn) for swap-pane window-swap-states call assertions.")

(defmacro kuro-mux-test--def-swap-pane-call (test-name fn-sym nav-fn)
  `(ert-deftest ,test-name ()
     ,(format "`%s' passes (selected . %s-result) to `window-swap-states'." fn-sym nav-fn)
     (let* ((win-a (selected-window))
            (win-b (list 'window 'fake))
            swapped-a swapped-b)
       (cl-letf (((symbol-function ',nav-fn) (lambda (&rest _) win-b))
                 ((symbol-function 'window-swap-states)
                  (lambda (a b) (setq swapped-a a swapped-b b))))
         (,fn-sym)
         (should (eq swapped-a win-a))
         (should (eq swapped-b win-b))))))

(kuro-mux-test--def-swap-pane-call kuro-mux-test-swap-pane-forward-calls-window-swap-states  kuro-mux-swap-pane-forward  next-window)
(kuro-mux-test--def-swap-pane-call kuro-mux-test-swap-pane-backward-calls-window-swap-states kuro-mux-swap-pane-backward previous-window)

(ert-deftest kuro-mux-test--all-swap-pane-calls-window-swap-states ()
  "Both swap-pane commands route (selected . nav-result) to window-swap-states."
  (dolist (entry kuro-mux-test--swap-pane-call-table)
    (pcase-let ((`(,_name ,fn-sym ,nav-fn) entry))
      (let* ((win-a (selected-window))
             (win-b (list 'window 'fake))
             swapped-a swapped-b)
        (cl-letf (((symbol-function nav-fn) (lambda (&rest _) win-b))
                  ((symbol-function 'window-swap-states)
                   (lambda (a b) (setq swapped-a a swapped-b b))))
          (funcall fn-sym)
          (should (eq swapped-a win-a))
          (should (eq swapped-b win-b)))))))

(kuro-mux-test--def-prefix-map-binding kuro-mux-test-swap-forward-bound-in-prefix-map  "}" kuro-mux-swap-pane-forward)
(kuro-mux-test--def-prefix-map-binding kuro-mux-test-swap-backward-bound-in-prefix-map "{" kuro-mux-swap-pane-backward)

(ert-deftest kuro-mux-test-mode-line-segment-defcustom-default-t ()
  "`kuro-mux-mode-line-segment' defcustom defaults to t."
  (should (eq kuro-mux-mode-line-segment t)))

(ert-deftest kuro-mux-test-buffer-mode-line-setup-adds-segment ()
  "`kuro-mux--buffer-mode-line-setup' appends the (:eval ...) segment."
  (with-temp-buffer
    (kuro-mux--buffer-mode-line-setup)
    (should (member '(:eval (kuro-mux--mode-line-segment)) mode-line-format))))

(ert-deftest kuro-mux-test-buffer-mode-line-setup-idempotent ()
  "`kuro-mux--buffer-mode-line-setup' does not add duplicates on repeated calls."
  (with-temp-buffer
    (kuro-mux--buffer-mode-line-setup)
    (kuro-mux--buffer-mode-line-setup)
    (should (= 1 (cl-count '(:eval (kuro-mux--mode-line-segment))
                            mode-line-format
                            :test #'equal)))))

;;; Group 22 — kuro-mux-other-window + kuro-mux-last + last-session tracking

(kuro-mux-test--def-commandp kuro-mux-test-other-window-is-interactive kuro-mux-other-window)

(defconst kuro-mux-test--other-window-error-table
  '((kuro-mux-test-other-window-errors-no-kuro-panes  nil)
    (kuro-mux-test-other-window-errors-single-pane    singleton))
  "Table of (test-name windows-type) for `kuro-mux-other-window' error conditions.")

(defmacro kuro-mux-test--def-other-window-error (test-name windows-type)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux-other-window' errors when windows=%s." windows-type)
     (cl-letf (((symbol-function 'kuro-mux--visible-windows)
                ,(if (eq windows-type 'singleton)
                     `(lambda () (list (selected-window)))
                   `(lambda () nil))))
       (should-error (kuro-mux-other-window) :type 'user-error))))

(kuro-mux-test--def-other-window-error kuro-mux-test-other-window-errors-no-kuro-panes  nil)
(kuro-mux-test--def-other-window-error kuro-mux-test-other-window-errors-single-pane    singleton)

(ert-deftest kuro-mux-test--all-other-window-errors-correct ()
  "All entries in `kuro-mux-test--other-window-error-table' produce user-errors."
  (dolist (entry kuro-mux-test--other-window-error-table)
    (pcase-let ((`(,_name ,windows-type) entry))
      (cl-letf (((symbol-function 'kuro-mux--visible-windows)
                 (if (eq windows-type 'singleton)
                     (lambda () (list (selected-window)))
                   (lambda () nil))))
        (should-error (kuro-mux-other-window) :type 'user-error)))))

(ert-deftest kuro-mux-test-other-window-selects-next-pane ()
  "`kuro-mux-other-window' selects the next window in the kuro-win list."
  (let* ((win-a (selected-window))
         (win-b (list 'window 'b))
         selected-win)
    (cl-letf (((symbol-function 'kuro-mux--visible-windows)
               (lambda () (list win-a win-b)))
              ((symbol-function 'select-window)
               (lambda (w) (setq selected-win w))))
      (kuro-mux-other-window)
      (should (eq selected-win win-b)))))

(ert-deftest kuro-mux-test-other-window-wraps-to-first ()
  "`kuro-mux-other-window' wraps to the first kuro window when at the last."
  (let* ((win-a (list 'window 'a))
         (win-b (selected-window))
         selected-win)
    (cl-letf (((symbol-function 'kuro-mux--visible-windows)
               (lambda () (list win-a win-b)))
              ((symbol-function 'select-window)
               (lambda (w) (setq selected-win w))))
      (kuro-mux-other-window)
      (should (eq selected-win win-a)))))

(kuro-mux-test--def-prefix-map-binding kuro-mux-test-other-window-bound-in-prefix-map "o" kuro-mux-other-window)

(kuro-mux-test--def-commandp kuro-mux-test-last-is-interactive kuro-mux-last)

(ert-deftest kuro-mux-test-last-errors-when-no-previous ()
  "`kuro-mux-last' signals user-error when kuro-mux--last-session is nil."
  (let ((kuro-mux--last-session nil))
    (should-error (kuro-mux-last) :type 'user-error)))

(ert-deftest kuro-mux-test-last-errors-when-session-dead ()
  "`kuro-mux-last' signals user-error and clears last-session when buffer is dead."
  (let* ((dead (generate-new-buffer "*kuro-mux-last-dead*"))
         (kuro-mux--last-session dead))
    (kill-buffer dead)
    (should-error (kuro-mux-last) :type 'user-error)))

(ert-deftest kuro-mux-test-last-switches-to-previous-session ()
  "`kuro-mux-last' calls `switch-to-buffer' with the recorded last session."
  (let* ((target (generate-new-buffer "*kuro-mux-last-target*"))
         (kuro-mux--last-session target)
         switched-to)
    (unwind-protect
        (cl-letf (((symbol-function 'switch-to-buffer)
                   (lambda (buf) (setq switched-to buf))))
          (kuro-mux-last)
          (should (eq switched-to target)))
      (kill-buffer target))))

(kuro-mux-test--def-prefix-map-binding kuro-mux-test-last-bound-in-prefix-map "L" kuro-mux-last)

(ert-deftest kuro-mux-test-track-installed-by-install-hooks ()
  "`kuro-mux--install-hooks' adds tracker to `window-selection-change-functions'."
  (let ((kuro-mode-hook nil)
        (kill-buffer-hook nil)
        (window-selection-change-functions nil))
    (kuro-mux--install-hooks)
    (should (memq #'kuro-mux--track-window-change
                  window-selection-change-functions))))

(ert-deftest kuro-mux-test-track-removed-by-uninstall-hooks ()
  "`kuro-mux--uninstall-hooks' removes tracker from `window-selection-change-functions'."
  (let ((kuro-mode-hook nil)
        (kill-buffer-hook nil)
        (window-selection-change-functions nil))
    (kuro-mux--install-hooks)
    (kuro-mux--uninstall-hooks)
    (should-not (memq #'kuro-mux--track-window-change
                      window-selection-change-functions))))

;;; Cross-group invariant dolist tests

(ert-deftest kuro-mux-test--all-commands-are-interactive ()
  "All kuro-mux-test--commandp-table entries are interactive commands."
  (dolist (entry kuro-mux-test--commandp-table)
    (pcase-let ((`(,_name ,fn-sym) entry))
      (should (commandp fn-sym)))))

(ert-deftest kuro-mux-test--all-prefix-map-bindings-correct ()
  "All kuro-mux-test--prefix-map-binding-table entries bind the correct function."
  (dolist (entry kuro-mux-test--prefix-map-binding-table)
    (pcase-let ((`(,_name ,key-str ,fn-sym) entry))
      (should (eq (lookup-key kuro-mux-prefix-map (kbd key-str)) fn-sym)))))

(provide 'kuro-mux-test-2)
;;; kuro-mux-test-2.el ends here
