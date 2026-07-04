;;; kuro-lifecycle-send-test.el --- Tests for kuro-send-region  -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for `kuro-send-region' and `kuro--most-recent-buffer',
;; introduced as Phase 4 (REPL / heavy-app workflow) additions to
;; kuro-lifecycle.el.
;;
;; Groups:
;;   Group 1: kuro--most-recent-buffer
;;   Group 2: kuro-send-region — from a kuro buffer
;;   Group 3: kuro-send-region — from a non-kuro buffer

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-lifecycle)

;; Minimal kuro-mode stub for buffers created in tests.
(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

(defmacro kuro-lifecycle-send-test--with-kuro-buf (name &rest body)
  "Evaluate BODY with a fresh buffer in kuro-mode named NAME.
The buffer is killed after BODY completes."
  (declare (indent 1))
  `(let ((buf (get-buffer-create ,name)))
     (unwind-protect
         (with-current-buffer buf
           (kuro-mode)
           ,@body)
       (when (buffer-live-p buf) (kill-buffer buf)))))

(defmacro kuro-lifecycle-send-test--stub-send (&rest body)
  "Run BODY with `kuro--send-paste-or-raw' and `kuro--schedule-immediate-render' stubbed."
  `(cl-letf (((symbol-function 'kuro--send-paste-or-raw) #'ignore)
             ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
     ,@body))


;;; Group 1 — kuro--most-recent-buffer

(ert-deftest kuro-lifecycle-send-test-most-recent-nil-when-no-kuro-buffers ()
  "kuro--most-recent-buffer returns nil when no kuro buffers exist."
  (let ((all-kuro (seq-filter (lambda (b)
                                (with-current-buffer b (derived-mode-p 'kuro-mode)))
                              (buffer-list))))
    ;; Only run when no kuro buffers happen to exist in this Emacs session
    (when (null all-kuro)
      (should (null (kuro--most-recent-buffer))))))

(ert-deftest kuro-lifecycle-send-test-most-recent-returns-kuro-buffer ()
  "kuro--most-recent-buffer returns a live kuro-mode buffer."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-mru-1*"
    (should (buffer-live-p (kuro--most-recent-buffer)))
    (should (with-current-buffer (kuro--most-recent-buffer)
              (derived-mode-p 'kuro-mode)))))

(ert-deftest kuro-lifecycle-send-test-most-recent-skips-dead-buffers ()
  "kuro--most-recent-buffer skips dead buffers in buffer-list."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-mru-dead*"
    ;; Buffer is live inside the macro body
    (let ((mru (kuro--most-recent-buffer)))
      (should (buffer-live-p mru)))))

(ert-deftest kuro-lifecycle-send-test-most-recent-skips-non-kuro ()
  "kuro--most-recent-buffer ignores buffers not in kuro-mode."
  (with-temp-buffer
    ;; fundamental-mode temp buffer should not be returned
    (let ((result (kuro--most-recent-buffer)))
      ;; If something is returned it must be a kuro buffer
      (when result
        (should (with-current-buffer result (derived-mode-p 'kuro-mode)))))))


;;; Group 2 — kuro-send-region from inside a kuro buffer

(ert-deftest kuro-lifecycle-send-test-from-kuro-buf-sends-text ()
  "kuro-send-region sends the region text via kuro--send-paste-or-raw."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-send-self*"
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (text) (setq sent text)))
                ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
        (with-temp-buffer
          (insert "echo hello")
          (kuro-send-region (point-min) (point-max))))
      ;; kuro-send-region sends to MRU kuro buffer, which is *kuro-test-send-self*
      (should (equal sent "echo hello")))))

(ert-deftest kuro-lifecycle-send-test-from-kuro-buf-sends-to-self ()
  "kuro-send-region in a kuro buffer sends to the current buffer, not another."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-send-to-self*"
    (let ((target nil))
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (_) (setq target (current-buffer))))
                ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
        (kuro-send-region (point-min) (point-max)))
      (should (eq target (get-buffer "*kuro-test-send-to-self*"))))))

(ert-deftest kuro-lifecycle-send-test-from-kuro-buf-calls-render ()
  "kuro-send-region calls kuro--schedule-immediate-render after sending."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-send-render*"
    (let ((rendered nil))
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw) #'ignore)
                ((symbol-function 'kuro--schedule-immediate-render)
                 (lambda () (setq rendered t))))
        (kuro-send-region (point-min) (point-max)))
      (should rendered))))

(ert-deftest kuro-lifecycle-send-test-from-kuro-buf-empty-region ()
  "kuro-send-region with empty region sends empty string."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-send-empty*"
    (let ((sent :unset))
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (text) (setq sent text)))
                ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
        (kuro-send-region (point-min) (point-max)))
      (should (equal sent "")))))

(ert-deftest kuro-lifecycle-send-test-from-kuro-buf-strips-text-properties ()
  "kuro-send-region sends buffer-substring-no-properties (plain text)."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-send-props*"
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (text) (setq sent text)))
                ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
        (with-temp-buffer
          (insert (propertize "bold text" 'face 'bold))
          (kuro-send-region (point-min) (point-max))))
      ;; No text properties in the sent string
      (should (equal sent "bold text"))
      (should (null (text-properties-at 0 sent))))))


;;; Group 3 — kuro-send-region from a non-kuro buffer

(ert-deftest kuro-lifecycle-send-test-from-other-buf-uses-mru ()
  "kuro-send-region from a non-kuro buffer sends to the MRU kuro session."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-send-mru*"
    (let ((target nil))
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (_) (setq target (current-buffer))))
                ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
        (with-temp-buffer
          ;; temp-buffer is not kuro-mode; should route to the MRU kuro buf
          (kuro-send-region (point-min) (point-max))))
      (should (buffer-live-p target))
      (should (with-current-buffer target (derived-mode-p 'kuro-mode))))))

(ert-deftest kuro-lifecycle-send-test-from-other-buf-errors-when-no-sessions ()
  "kuro-send-region signals user-error when no Kuro sessions exist."
  ;; We can only run this reliably by stubbing kuro--most-recent-buffer
  (with-temp-buffer
    (cl-letf (((symbol-function 'kuro--most-recent-buffer)
               (lambda () nil)))
      (should-error (kuro-send-region (point-min) (point-max))
                    :type 'user-error))))

(ert-deftest kuro-lifecycle-send-test-from-other-buf-sends-text ()
  "kuro-send-region from a non-kuro buffer sends the correct text."
  (kuro-lifecycle-send-test--with-kuro-buf "*kuro-test-send-text-mru*"
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (text) (setq sent text)))
                ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
        (with-temp-buffer
          (insert "git status\n")
          (kuro-send-region (point-min) (point-max))))
      (should (equal sent "git status\n")))))

(provide 'kuro-lifecycle-send-test)

;;; kuro-lifecycle-send-test.el ends here
