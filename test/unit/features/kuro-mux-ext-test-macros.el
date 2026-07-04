;;; kuro-mux-ext-test-macros.el --- Macro helpers for kuro-mux-ext tests  -*- lexical-binding: t; -*-

;;; Code:

(eval-and-compile
  (require 'cl-lib))
(require 'ert)
(require 'kuro-mux-ext-test-cases)

(defmacro kuro-mux-ext-test--with-buf (&rest body)
  "Run BODY in a fresh kuro-mode buffer, cleaned up on exit."
  `(let ((buf (generate-new-buffer " *kuro-ext-test*")))
     (unwind-protect
         (with-current-buffer buf
           (kuro-mode)
           ,@body)
       (when (buffer-live-p buf) (kill-buffer buf)))))

(defmacro kuro-mux-ext-test--def-interactive-command (test-name fn-sym)
  "Define TEST-NAME asserting FN-SYM is interactive."
  `(ert-deftest ,test-name ()
     ,(format "`%s' is an interactive command." fn-sym)
     (should (commandp #',fn-sym))))

(defmacro kuro-mux-ext-test--deftest-interactive-commands ()
  "Define all interactive command tests."
  `(progn
     ,@(cl-loop for (test-name fn-sym) in kuro-mux-ext-test--interactive-command-table
                collect `(kuro-mux-ext-test--def-interactive-command ,test-name ,fn-sym))))

(defmacro kuro-mux-ext-test--def-auto-save-on-exit
    (test-name auto-save-layout live-sessions expected-saved)
  "Define TEST-NAME for `kuro-mux--auto-save-on-exit'."
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux--auto-save-on-exit' saved=%S when enabled=%S sessions=%S."
              expected-saved auto-save-layout live-sessions)
     (let ((kuro-mux-auto-save-layout ,auto-save-layout)
           saved)
       (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                  (lambda () ',live-sessions))
                 ((symbol-function 'kuro-mux-save-layout)
                  (lambda () (setq saved t))))
         (kuro-mux--auto-save-on-exit)
         (should (eq (not (null saved)) ,(not (null expected-saved))))))))

(defmacro kuro-mux-ext-test--deftest-auto-save-on-exit ()
  "Define all `kuro-mux--auto-save-on-exit' tests."
  `(progn
     ,@(cl-loop for (test-name auto-save-layout live-sessions expected-saved)
                in kuro-mux-ext-test--auto-save-on-exit-table
                collect
                `(kuro-mux-ext-test--def-auto-save-on-exit
                  ,test-name ,auto-save-layout ,live-sessions ,expected-saved))))

(defmacro kuro-mux-ext-test--def-tab-bar-update
    (test-name existing-tabs expected-new-tab fboundp-symbols)
  "Define TEST-NAME for `kuro-mux--tab-bar-update'."
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux--tab-bar-update' new-tab=%S for tabs=%S."
              expected-new-tab existing-tabs)
     (let ((new-tab-created nil)
           (real-fboundp (symbol-function 'fboundp)))
       (with-temp-buffer
         (let ((sess-buf (current-buffer)))
           (cl-letf (((symbol-function 'fboundp)
                      (lambda (sym)
                        (if (memq sym ',fboundp-symbols)
                            t
                          (funcall real-fboundp sym))))
                     ((symbol-function 'tab-bar-mode) #'ignore)
                     ((symbol-function 'kuro-mux--live-sessions)
                      (lambda () (list sess-buf)))
                     ((symbol-function 'kuro-mux--session-display-name)
                      (lambda (_) "test-session"))
                     ((symbol-function 'tab-bar-tabs)
                      (lambda () ',existing-tabs))
                     ((symbol-function 'tab-bar-new-tab)
                      (lambda () (setq new-tab-created t)))
                     ((symbol-function 'switch-to-buffer) #'ignore)
                     ((symbol-function 'tab-bar-rename-tab) #'ignore))
             (kuro-mux--tab-bar-update)
             (should (eq (not (null new-tab-created))
                         ,(not (null expected-new-tab))))))))))

(defmacro kuro-mux-ext-test--deftest-tab-bar-updates ()
  "Define all `kuro-mux--tab-bar-update' tests."
  `(progn
     ,@(cl-loop for (test-name existing-tabs expected-new-tab fboundp-symbols)
                in kuro-mux-ext-test--tab-bar-update-table
                collect
                `(kuro-mux-ext-test--def-tab-bar-update
                  ,test-name ,existing-tabs ,expected-new-tab ,fboundp-symbols))))

(provide 'kuro-mux-ext-test-macros)
;;; kuro-mux-ext-test-macros.el ends here
