;;; kuro-input-paste-test-macros.el --- Paste test macro generators  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'kuro-input-paste-test-cases)

(defmacro kuro-paste-test--capture-sent (&rest body)
  "Execute BODY with `kuro--send-paste' and render scheduling stubbed.
Returns strings passed to `kuro--send-paste', in call order."
  `(let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-paste)
                (lambda (s) (push s sent)))
               ((symbol-function 'kuro--schedule-immediate-render)
                (lambda () nil)))
       ,@body)
     (nreverse sent)))

(defmacro kuro-paste-test--capture-sent-in-buffer (&rest body)
  "Execute BODY in a fresh temp buffer with send stubbed; return sent list."
  `(with-temp-buffer
     (kuro-paste-test--capture-sent
      ,@body)))

(defmacro kuro-paste-test--def-yank-arg (name doc kills arg expected)
  "Define a `kuro--yank' arg test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((kill-ring nil))
       (with-temp-buffer
         (dolist (text ',kills)
           (kill-new text))
         (let ((kuro--bracketed-paste-mode nil)
               (sent (kuro-paste-test--capture-sent (kuro--yank ,arg))))
           (should (equal sent ',expected)))))))

(defmacro kuro-paste-test--deftest-yank-args ()
  "Define `kuro--yank' argument tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,kills ,arg ,expected))
          `(kuro-paste-test--def-yank-arg ,name ,doc ,kills ,arg ,expected))
        kuro-paste-test--yank-arg-cases)))

(defmacro kuro-paste-test--def-yank-error
    (name doc kills arg error-type)
  "Define a `kuro--yank' argument rejection test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((kill-ring nil))
       (with-temp-buffer
         (dolist (text ',kills)
           (kill-new text))
         (let ((kuro--bracketed-paste-mode nil))
           (should-error (kuro--yank ,arg) :type ',error-type))))))

(defmacro kuro-paste-test--deftest-yank-errors ()
  "Define `kuro--yank' argument rejection tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,kills ,arg ,error-type))
          `(kuro-paste-test--def-yank-error
            ,name ,doc ,kills ,arg ,error-type))
        kuro-paste-test--yank-error-cases)))

(defun kuro-paste-test--assert-sent (sent assertion)
  "Assert SENT according to ASSERTION plist."
  (if (plist-member assertion :expected)
      (should (equal sent (plist-get assertion :expected)))
    (error "Unknown paste assertion: %S" assertion)))

(defmacro kuro-paste-test--def-yank-send (name doc kill-text bracketed-p assertion)
  "Define a `kuro--yank' send-shape test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((kill-ring nil))
       (with-temp-buffer
         (kill-new ,kill-text)
         (let* ((kuro--bracketed-paste-mode ,bracketed-p)
                (sent (kuro-paste-test--capture-sent (kuro--yank))))
           (kuro-paste-test--assert-sent sent ,assertion))))))

(defmacro kuro-paste-test--deftest-yank-sends ()
  "Define `kuro--yank' send-shape tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,kill-text ,bracketed-p ,assertion))
          `(kuro-paste-test--def-yank-send
            ,name ,doc ,kill-text ,bracketed-p ,assertion))
        kuro-paste-test--yank-send-cases)))

(defmacro kuro-paste-test--def-yank-pop-send
    (name doc kill-text last-command-symbol bracketed-p arg assertion)
  "Define a `kuro--yank-pop' send-shape test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((kill-ring nil))
       (with-temp-buffer
         (kill-new ,kill-text)
         (let ((last-command ',last-command-symbol)
               (kuro--bracketed-paste-mode ,bracketed-p))
           (let ((sent (kuro-paste-test--capture-sent (kuro--yank-pop ,arg))))
             (kuro-paste-test--assert-sent sent ,assertion)))))))

(defmacro kuro-paste-test--deftest-yank-pop-sends ()
  "Define `kuro--yank-pop' send-shape tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,kill-text ,last-command-symbol
                               ,bracketed-p ,arg ,assertion))
          `(kuro-paste-test--def-yank-pop-send
            ,name ,doc ,kill-text ,last-command-symbol
            ,bracketed-p ,arg ,assertion))
        kuro-paste-test--yank-pop-send-cases)))

(defmacro kuro-paste-test--def-yank-pop-error
    (name doc last-command-symbol bracketed-p arg error-type)
  "Define a `kuro--yank-pop' error test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((last-command ',last-command-symbol)
           (kuro--bracketed-paste-mode ,bracketed-p))
       (should-error (kuro--yank-pop ,arg) :type ',error-type))))

(defmacro kuro-paste-test--deftest-yank-pop-errors ()
  "Define `kuro--yank-pop' error tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,last-command-symbol
                               ,bracketed-p ,arg ,error-type))
          `(kuro-paste-test--def-yank-pop-error
            ,name ,doc ,last-command-symbol ,bracketed-p ,arg ,error-type))
        kuro-paste-test--yank-pop-error-cases)))

(defmacro kuro-paste-test--def-buffer-local
    (name doc variable first-value second-value)
  "Define a buffer-local isolation test for VARIABLE named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((buf1 (get-buffer-create (format " *%s-1*" ',name)))
           (buf2 (get-buffer-create (format " *%s-2*" ',name))))
       (unwind-protect
           (progn
             (with-current-buffer buf1
               (setq-local ,variable ,first-value))
             (with-current-buffer buf2
               (setq-local ,variable ,second-value))
             (should (equal (with-current-buffer buf1 ,variable) ,first-value))
             (should (equal (with-current-buffer buf2 ,variable) ,second-value)))
         (kill-buffer buf1)
         (kill-buffer buf2)))))

(defmacro kuro-paste-test--deftest-buffer-locals ()
  "Define buffer-local isolation tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,variable ,first-value ,second-value))
          `(kuro-paste-test--def-buffer-local
            ,name ,doc ,variable ,first-value ,second-value))
        kuro-paste-test--buffer-local-cases)))

(defmacro kuro-paste-test--def-send-paste-or-raw
    (name doc text bracketed-p assertion)
  "Define a `kuro--send-paste-or-raw' test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let* ((text ,text)
            (sent (kuro-paste-test--capture-sent-in-buffer
                   (setq-local kuro--bracketed-paste-mode ,bracketed-p)
                   (kuro--send-paste-or-raw text))))
       (kuro-paste-test--assert-sent sent ,assertion))))

(defmacro kuro-paste-test--deftest-send-paste-or-raws ()
  "Define `kuro--send-paste-or-raw' tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,text ,bracketed-p ,assertion))
          `(kuro-paste-test--def-send-paste-or-raw
            ,name ,doc ,text ,bracketed-p ,assertion))
        kuro-paste-test--send-paste-or-raw-cases)))

(defmacro kuro-paste-test--def-yank-render (name doc kill-text)
  "Define a `kuro--yank' render scheduling test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((kill-ring nil)
           (render-called nil))
       (with-temp-buffer
         (kill-new ,kill-text)
         (let ((kuro--bracketed-paste-mode nil))
           (cl-letf (((symbol-function 'kuro--send-paste)
                      (lambda (_s) nil))
                     ((symbol-function 'kuro--schedule-immediate-render)
                      (lambda () (setq render-called t))))
             (kuro--yank)))
         (should render-called)))))

(defmacro kuro-paste-test--deftest-yank-renders ()
  "Define `kuro--yank' render scheduling tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,kill-text))
          `(kuro-paste-test--def-yank-render ,name ,doc ,kill-text))
        kuro-paste-test--yank-render-cases)))

(defmacro kuro-paste-test--def-yank-pop-render
    (name doc kill-text last-command-symbol arg)
  "Define a `kuro--yank-pop' render scheduling test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((kill-ring nil)
           (render-called nil)
           (sent nil))
       (with-temp-buffer
         (kill-new ,kill-text)
         (let ((last-command ',last-command-symbol)
               (kuro--bracketed-paste-mode nil))
           (cl-letf (((symbol-function 'kuro--send-paste)
                      (lambda (s) (push s sent)))
                     ((symbol-function 'kuro--schedule-immediate-render)
                      (lambda () (setq render-called t))))
             (kuro--yank-pop ,arg)))
         (should (equal (nreverse sent) (list ,kill-text)))
         (should render-called)))))

(defmacro kuro-paste-test--deftest-yank-pop-renders ()
  "Define `kuro--yank-pop' render scheduling tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,kill-text ,last-command-symbol ,arg))
          `(kuro-paste-test--def-yank-pop-render
            ,name ,doc ,kill-text ,last-command-symbol ,arg))
        kuro-paste-test--yank-pop-render-cases)))

(defmacro kuro-paste-test--def-yank-pop-last-command
    (name doc kill-text last-command-symbol bracketed-p arg assertion)
  "Define a valid-last-command `kuro--yank-pop' test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((kill-ring nil))
       (with-temp-buffer
         (kill-new ,kill-text)
         (let ((last-command ',last-command-symbol)
               (kuro--bracketed-paste-mode ,bracketed-p))
           (let ((sent (kuro-paste-test--capture-sent (kuro--yank-pop ,arg))))
             (kuro-paste-test--assert-sent sent ,assertion)))))))

(defmacro kuro-paste-test--deftest-yank-pop-last-commands ()
  "Define valid-last-command `kuro--yank-pop' tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,kill-text ,last-command-symbol
                               ,bracketed-p ,arg ,assertion))
          `(kuro-paste-test--def-yank-pop-last-command
            ,name ,doc ,kill-text ,last-command-symbol
            ,bracketed-p ,arg ,assertion))
        kuro-paste-test--yank-pop-last-command-cases)))

(defmacro kuro-paste-test--def-yank-extra
    (name doc kill-text bracketed-p assertion)
  "Define an extra `kuro--yank' dispatch-shape test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (let ((kill-ring nil))
       (with-temp-buffer
         (kill-new ,kill-text)
         (let* ((kuro--bracketed-paste-mode ,bracketed-p)
                (sent (kuro-paste-test--capture-sent (kuro--yank))))
           (kuro-paste-test--assert-sent sent ,assertion))))))

(defmacro kuro-paste-test--deftest-yank-extras ()
  "Define extra `kuro--yank' dispatch-shape tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,kill-text ,bracketed-p ,assertion))
          `(kuro-paste-test--def-yank-extra
            ,name ,doc ,kill-text ,bracketed-p ,assertion))
        kuro-paste-test--yank-extra-cases)))

(defmacro kuro-paste-test--deftest-extra-errors ()
  "Define extra paste error tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,last-command-symbol
                               ,bracketed-p ,arg ,error-type))
          `(kuro-paste-test--def-yank-pop-error
            ,name ,doc ,last-command-symbol ,bracketed-p ,arg ,error-type))
        kuro-paste-test--extra-error-cases)))

(defmacro kuro-paste-test--def-initial-value
    (name doc variable expected)
  "Define a fresh-buffer initial value test named NAME."
  `(ert-deftest ,name ()
     ,doc
     (with-temp-buffer
       (should (equal ,variable ,expected)))))

(defmacro kuro-paste-test--deftest-initial-values ()
  "Define fresh-buffer initial value tests from data."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,doc ,variable ,expected))
          `(kuro-paste-test--def-initial-value ,name ,doc ,variable ,expected))
        kuro-paste-test--initial-value-cases)))

(provide 'kuro-input-paste-test-macros)
;;; kuro-input-paste-test-macros.el ends here
