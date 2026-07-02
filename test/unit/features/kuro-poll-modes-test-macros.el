;;; kuro-poll-modes-test-macros.el --- Macro helpers for kuro-poll-modes tests  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-poll-modes)

(defmacro kuro-poll-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with poll-modes state initialized."
  `(with-temp-buffer
     (setq-local kuro--initialized t)
     (setq-local kuro--mode-poll-frame-count 0)
     (setq-local kuro--prompt-positions nil)
     (setq-local kuro--application-cursor-keys-mode nil)
     (setq-local kuro--app-keypad-mode nil)
     (setq-local kuro--mouse-mode nil)
     (setq-local kuro--mouse-sgr nil)
     (setq-local kuro--mouse-pixel-mode nil)
     (setq-local kuro--bracketed-paste-mode nil)
     (setq-local kuro--keyboard-flags 0)
     (setq-local kuro-kill-buffer-on-exit nil)
     ,@body))

(defmacro kuro-poll-test--with-osc52-response (kill-body &rest body)
  "Run `kuro--send-osc52-clipboard-response' with KILL-BODY as the `current-kill' form.
BODY is evaluated with `sent' bound to the captured `kuro--send-key' argument."
  `(kuro-poll-test--with-buffer
     (let ((sent nil))
       (cl-letf (((symbol-function 'current-kill)
                  (lambda (_n _no-move) ,kill-body))
                 ((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
         (kuro--send-osc52-clipboard-response)
         ,@body))))

(defmacro kuro-poll-test--check-exit (alive-p kill-flag expected-form)
  "Run `kuro--check-process-exit' with process-alive ALIVE-P and kill flag KILL-FLAG.
EXPECTED-FORM is `should' or `should-not' - asserts whether `kuro-kill' was called."
  `(kuro-poll-test--with-buffer
     (setq-local kuro-kill-buffer-on-exit ,kill-flag)
     (let ((kill-called nil))
       (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () ,alive-p))
                 ((symbol-function 'kuro-kill) (lambda () (setq kill-called t))))
         (kuro--check-process-exit)
         (,expected-form kill-called)))))

(defmacro kuro-poll-test--assert-default-notify (title body expected-str)
  "Call `kuro--default-notify' with TITLE and BODY; assert echo-area message = EXPECTED-STR."
  `(let ((shown nil))
     (cl-letf (((symbol-function 'require) (lambda (&rest _) nil))
               ((symbol-function 'message)
                (lambda (fmt &rest args) (setq shown (apply #'format fmt args)))))
       (kuro--default-notify ,title ,body)
       (should (equal shown ,expected-str)))))

(defmacro kuro-poll-test--with-tier1-stubs (modes-fn &rest body)
  "Run BODY with the five tier1 side-effect fns stubbed to `#\\='ignore'.
MODES-FN is bound to `kuro--get-terminal-modes'."
  `(kuro-poll-test--with-buffer
     (cl-letf (((symbol-function 'kuro--get-terminal-modes)         ,modes-fn)
               ((symbol-function 'kuro--poll-cwd)                   #'ignore)
               ((symbol-function 'kuro--handle-clipboard-actions)   #'ignore)
               ((symbol-function 'kuro--poll-prompt-mark-updates)   #'ignore)
               ((symbol-function 'kuro--poll-image-events)          #'ignore)
                 ((symbol-function 'kuro--check-process-exit)         #'ignore))
        ,@body)))

(defmacro kuro-poll-test--with-clipboard-write-action (policy text accepted-p &rest body)
  "Run BODY with a clipboard write action under POLICY.
TEXT is returned from `kuro--poll-clipboard-actions'. ACCEPTED-P controls `yes-or-no-p'.
BODY can assert on `kill-new-called' and `kill-new-called-with'."
  `(kuro-poll-test--with-buffer
     (let ((kuro-clipboard-policy ,policy)
           (kill-new-called nil)
           (kill-new-called-with nil))
       (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                  (lambda () (list (list 'write ,text "clipboard"))))
                 ((symbol-function 'yes-or-no-p) (lambda (_prompt) ,accepted-p))
                 ((symbol-function 'kill-new)
                  (lambda (text)
                    (setq kill-new-called t
                          kill-new-called-with text)))
                 ((symbol-function 'message) #'ignore))
         ,@body))))

(defmacro kuro-poll-test--with-clipboard-query-action (policy clip-text &rest body)
  "Run BODY with a clipboard query action under POLICY.
CLIP-TEXT is returned from `current-kill'. BODY can assert on `sent-key'."
  `(kuro-poll-test--with-buffer
     (let ((kuro-clipboard-policy ,policy)
           (sent-key nil))
       (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                  (lambda () '((query nil "clipboard"))))
                 ((symbol-function 'current-kill)
                  (lambda (_n _do-not-move) ,clip-text))
                 ((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent-key s)))
                 ((symbol-function 'message) #'ignore))
         ,@body))))

(defmacro kuro-poll-test--assert-tier1 (frame expected-form)
  "Assert whether `kuro--poll-tier1-modes' fires when FRAME is the current count.
EXPECTED-FORM is `should' or `should-not'."
  `(kuro-poll-test--with-buffer
     (setq kuro--mode-poll-frame-count ,frame)
     (let ((tier1-called nil))
       (cl-letf (((symbol-function 'kuro--poll-tier1-modes)
                  (lambda () (setq tier1-called t)))
                 ((symbol-function 'kuro--poll-osc-events) #'ignore))
         (kuro--poll-terminal-modes)
         (,expected-form tier1-called)))))

(defmacro kuro-poll-test--assert-tier2 (frame expected-form)
  "Assert whether `kuro--poll-osc-events' fires when FRAME is the current count.
EXPECTED-FORM is `should' or `should-not'."
  `(kuro-poll-test--with-buffer
     (setq kuro--mode-poll-frame-count ,frame)
     (let ((osc-called nil))
       (cl-letf (((symbol-function 'kuro--poll-tier1-modes) #'ignore)
                 ((symbol-function 'kuro--poll-osc-events)
                  (lambda () (setq osc-called t))))
         (kuro--poll-terminal-modes)
         (,expected-form osc-called)))))

(provide 'kuro-poll-modes-test-macros)
;;; kuro-poll-modes-test-macros.el ends here
