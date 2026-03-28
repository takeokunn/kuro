;;; kuro-input-mouse-ext2-test.el --- Extended tests for kuro-input-mouse.el (part 2)  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Extended ERT tests for kuro-input-mouse.el (Groups 23–24).
;; Split from kuro-input-mouse-ext-test.el for file-size management.
;;
;; Covers: scrollback fallback path (kuro--mouse-scroll-up/down with mode=0),
;; and kuro--def-mouse-cmd macro code-generation and runtime dispatch.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; kuro-input-mouse requires kuro-ffi at load time.  Stub the FFI symbols
;; it uses so the file loads in a batch/test environment without the module.
(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))
(unless (fboundp 'kuro--mouse-mode-query)
  (defalias 'kuro--mouse-mode-query (lambda () 0)))
(unless (fboundp 'kuro--scroll-up)
  (defalias 'kuro--scroll-up (lambda (_n) nil)))
(unless (fboundp 'kuro--scroll-down)
  (defalias 'kuro--scroll-down (lambda (_n) nil)))
(unless (fboundp 'kuro--get-scroll-offset)
  (defalias 'kuro--get-scroll-offset (lambda () 0)))
(unless (fboundp 'kuro--render-cycle)
  (defalias 'kuro--render-cycle (lambda () nil)))
(unless (fboundp 'kuro--update-scroll-indicator)
  (defalias 'kuro--update-scroll-indicator (lambda () nil)))

(require 'kuro-input-mouse)


;;; Test helpers

(defmacro kuro-input-mouse-test--with-send (mode sgr pixel col row &rest body)
  "Execute BODY with mouse stubs installed; bind `sent' to capture kuro--send-key arg.
MODE is kuro--mouse-mode, SGR is kuro--mouse-sgr, PIXEL is kuro--mouse-pixel-mode.
COL and ROW are the cell coords returned by posn-col-row (and posn-x-y)."
  (declare (indent 5))
  `(with-temp-buffer
     (setq-local kuro--mouse-mode ,mode
                 kuro--mouse-sgr ,sgr
                 kuro--mouse-pixel-mode ,pixel)
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'event-start)
                  (lambda (_ev) 'fake-pos))
                 ((symbol-function 'posn-col-row)
                  (lambda (_pos) (cons ,col ,row)))
                 ((symbol-function 'posn-x-y)
                  (lambda (_pos) (cons ,col ,row))))
         ,@body))))

(defmacro kuro-input-mouse-test--with-send-and-type (mode sgr pixel col row event-type &rest body)
  "Like `kuro-input-mouse-test--with-send' but also stubs `event-basic-type' to return EVENT-TYPE."
  (declare (indent 6))
  `(with-temp-buffer
     (setq-local kuro--mouse-mode ,mode
                 kuro--mouse-sgr ,sgr
                 kuro--mouse-pixel-mode ,pixel)
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'event-basic-type)
                  (lambda (_ev) ,event-type))
                 ((symbol-function 'event-start)
                  (lambda (_ev) 'fake-pos))
                 ((symbol-function 'posn-col-row)
                  (lambda (_pos) (cons ,col ,row)))
                 ((symbol-function 'posn-x-y)
                  (lambda (_pos) (cons ,col ,row))))
         ,@body))))

(defmacro kuro-mouse-test--with-event (col row &rest body)
  "Execute BODY with event-start, posn-col-row, and posn-x-y stubbed.
COL and ROW are the 0-based cell coordinates posn-col-row returns.
posn-x-y returns the same values as pixel coordinates for pixel-mode tests."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'event-start)
               (lambda (_ev) 'fake-pos))
              ((symbol-function 'posn-col-row)
               (lambda (_pos) (cons ,col ,row)))
              ((symbol-function 'posn-x-y)
               (lambda (_pos) (cons ,col ,row))))
     ,@body))


;;; Group 23: kuro--mouse-scroll-up/down scrollback fallback path
;;
;; When kuro--mouse-mode is 0 (mouse tracking off) and kuro--initialized is
;; non-nil, scroll-up/down should scroll the terminal scrollback instead of
;; sending PTY events.  When NOT initialized, both should be no-ops.

(ert-deftest kuro-input-mouse-scroll-up-mode0-increments-offset ()
  "kuro--mouse-scroll-up with mouse-mode=0 calls kuro--scroll-up and updates offset."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--initialized t
                kuro--scroll-offset 0)
    (let ((scroll-called nil)
          (render-called nil))
      (cl-letf (((symbol-function 'kuro--scroll-up)
                 (lambda (n) (setq scroll-called n)))
                ((symbol-function 'kuro--get-scroll-offset)
                 (lambda () 5))
                ((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t))))
        (kuro-mouse-test--with-event 0 0
          (kuro--mouse-scroll-up)))
      ;; kuro--scroll-up must have been called with kuro--mouse-scroll-lines
      (should (= scroll-called kuro--mouse-scroll-lines))
      ;; kuro--get-scroll-offset returned 5 → offset should be 5
      (should (= kuro--scroll-offset 5))
      ;; render-cycle must have been triggered
      (should render-called))))

(ert-deftest kuro-input-mouse-scroll-down-mode0-decrements-offset ()
  "kuro--mouse-scroll-down with mouse-mode=0 calls kuro--scroll-down and updates offset."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--initialized t
                kuro--scroll-offset 10)
    (let ((scroll-called nil)
          (render-called nil))
      (cl-letf (((symbol-function 'kuro--scroll-down)
                 (lambda (n) (setq scroll-called n)))
                ((symbol-function 'kuro--get-scroll-offset)
                 (lambda () 5))
                ((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t))))
        (kuro-mouse-test--with-event 0 0
          (kuro--mouse-scroll-down)))
      (should (= scroll-called kuro--mouse-scroll-lines))
      ;; kuro--get-scroll-offset returned 5 → offset should be 5
      (should (= kuro--scroll-offset 5))
      (should render-called))))

(ert-deftest kuro-input-mouse-scroll-down-mode0-offset-floor-at-zero ()
  "kuro--mouse-scroll-down with offset=0 stays at 0 (never goes negative).
When kuro--get-scroll-offset returns nil, the fallback formula
(max 0 (- 0 5)) = 0 prevents negative offsets."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--initialized t
                kuro--scroll-offset 0)
    (cl-letf (((symbol-function 'kuro--scroll-down)
               (lambda (_n) nil))
              ((symbol-function 'kuro--get-scroll-offset)
               (lambda () nil))
              ((symbol-function 'kuro--render-cycle)
               (lambda () nil)))
      (kuro-mouse-test--with-event 0 0
        (kuro--mouse-scroll-down)))
    ;; (max 0 (- 0 5)) = 0
    (should (= kuro--scroll-offset 0))))

(ert-deftest kuro-input-mouse-scroll-up-not-initialized-is-noop ()
  "kuro--mouse-scroll-up is a no-op when kuro--initialized is nil (mode=0)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--initialized nil
                kuro--scroll-offset 0)
    (let ((scroll-called nil)
          (render-called nil))
      (cl-letf (((symbol-function 'kuro--scroll-up)
                 (lambda (_n) (setq scroll-called t)))
                ((symbol-function 'kuro--get-scroll-offset)
                 (lambda () 0))
                ((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t))))
        (kuro-mouse-test--with-event 0 0
          (kuro--mouse-scroll-up)))
      (should-not scroll-called)
      (should-not render-called)
      (should (= kuro--scroll-offset 0)))))

(ert-deftest kuro-input-mouse-scroll-down-not-initialized-is-noop ()
  "kuro--mouse-scroll-down is a no-op when kuro--initialized is nil (mode=0)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--initialized nil
                kuro--scroll-offset 5)
    (let ((scroll-called nil)
          (render-called nil))
      (cl-letf (((symbol-function 'kuro--scroll-down)
                 (lambda (_n) (setq scroll-called t)))
                ((symbol-function 'kuro--get-scroll-offset)
                 (lambda () 0))
                ((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t))))
        (kuro-mouse-test--with-event 0 0
          (kuro--mouse-scroll-down)))
      (should-not scroll-called)
      (should-not render-called)
      ;; offset must remain unchanged
      (should (= kuro--scroll-offset 5)))))

(ert-deftest kuro-input-mouse-scroll-up-mode-positive-sends-pty-event ()
  "kuro--mouse-scroll-up with mouse-mode>0 sends PTY event, does NOT scroll scrollback."
  (let ((scroll-called nil))
    (kuro-input-mouse-test--with-send 1000 t nil 0 0
      (setq-local kuro--initialized t
                  kuro--scroll-offset 0)
      (cl-letf (((symbol-function 'kuro--scroll-up)
                 (lambda (_n) (setq scroll-called t))))
        (kuro--mouse-scroll-up))
      ;; PTY event must have been sent (button=64, SGR)
      (should (equal sent "\e[<64;1;1M"))
      ;; kuro--scroll-up must NOT have been called
      (should-not scroll-called)
      ;; offset must remain unchanged
      (should (= kuro--scroll-offset 0)))))

(ert-deftest kuro-input-mouse-scroll-up-mode0-fallback-when-get-offset-nil ()
  "kuro--mouse-scroll-up falls back to (+ offset lines) when kuro--get-scroll-offset returns nil."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--initialized t
                kuro--scroll-offset 10)
    (cl-letf (((symbol-function 'kuro--scroll-up)
               (lambda (_n) nil))
              ((symbol-function 'kuro--get-scroll-offset)
               (lambda () nil))
              ((symbol-function 'kuro--render-cycle)
               (lambda () nil)))
      (kuro-mouse-test--with-event 0 0
        (kuro--mouse-scroll-up)))
    ;; (max 0 (+ 10 5)) = 15
    (should (= kuro--scroll-offset 15))))

(ert-deftest kuro-input-mouse-scroll-down-mode0-fallback-clamps-to-zero ()
  "kuro--mouse-scroll-down fallback (- offset lines) clamps to 0 when offset < lines."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--initialized t
                kuro--scroll-offset 2)
    (cl-letf (((symbol-function 'kuro--scroll-down)
               (lambda (_n) nil))
              ((symbol-function 'kuro--get-scroll-offset)
               (lambda () nil))
              ((symbol-function 'kuro--render-cycle)
               (lambda () nil)))
      (kuro-mouse-test--with-event 0 0
        (kuro--mouse-scroll-down)))
    ;; (max 0 (- 2 5)) = 0
    (should (= kuro--scroll-offset 0))))

;;; Group 24: kuro--def-mouse-cmd macro — code generation and runtime dispatch
;;
;; kuro--def-mouse-cmd expands to a single `defun' that calls
;; `kuro--dispatch-mouse-event' with a btn-form and a literal press value.
;; Tests verify:
;;   (a) code-generation: the generated symbol is fboundp and commandp after
;;       the macro fires at load time (kuro--mouse-press / kuro--mouse-release
;;       are the canonical instances defined at top-level in the source file),
;;   (b) custom invocation: a test-local symbol defined by the macro is also
;;       fboundp immediately after expansion,
;;   (c) runtime/press path: a literal-btn command (press=t) forwards the
;;       correct button number to the PTY via kuro--send-key,
;;   (d) runtime/release path: a literal-btn command (press=nil) sends a
;;       release-encoded sequence.

(ert-deftest kuro-input-mouse-def-cmd-press-is-fboundp ()
  "kuro--def-mouse-cmd generates kuro--mouse-press as a defined function."
  (should (fboundp 'kuro--mouse-press)))

(ert-deftest kuro-input-mouse-def-cmd-release-is-fboundp ()
  "kuro--def-mouse-cmd generates kuro--mouse-release as a defined function."
  (should (fboundp 'kuro--mouse-release)))

(ert-deftest kuro-input-mouse-def-cmd-press-is-interactive ()
  "kuro--mouse-press is an interactive command (commandp returns t)."
  (should (commandp 'kuro--mouse-press)))

(ert-deftest kuro-input-mouse-def-cmd-release-is-interactive ()
  "kuro--mouse-release is an interactive command (commandp returns t)."
  (should (commandp 'kuro--mouse-release)))

(ert-deftest kuro-input-mouse-def-cmd-custom-symbol-becomes-fboundp ()
  "kuro--def-mouse-cmd with a fresh name defines that symbol as a function.
The macro expansion produces a defun, so the symbol is fboundp afterward."
  ;; Unintern the test symbol first to ensure a clean state.
  (unintern 'kuro--test-mouse-cmd-probe obarray)
  (eval '(kuro--def-mouse-cmd kuro--test-mouse-cmd-probe
           42
           t
           "Test-only probe command generated by kuro--def-mouse-cmd.")
        t)
  (should (fboundp 'kuro--test-mouse-cmd-probe))
  ;; Clean up: remove the test symbol from obarray.
  (unintern 'kuro--test-mouse-cmd-probe obarray))

(ert-deftest kuro-input-mouse-def-cmd-press-path-sends-correct-sequence ()
  "Generated press command (press=t, literal btn=1) sends the correct SGR sequence.
kuro--def-mouse-cmd expands btn-form at call time; with a literal integer the
dispatch macro resolves to a single kuro--send-key call with the right bytes."
  ;; Define a test-local command with btn=1 and press=t.
  (eval '(kuro--def-mouse-cmd kuro--test-mouse-press-btn1
           1
           t
           "Test press command for button 1.")
        t)
  (unwind-protect
      (kuro-input-mouse-test--with-send 1000 t nil 0 0
        (kuro--test-mouse-press-btn1)
        ;; SGR: button=1, col1=1, row1=1, press → ESC[<1;1;1M
        (should (equal sent "\e[<1;1;1M")))
    (unintern 'kuro--test-mouse-press-btn1 obarray)))

(ert-deftest kuro-input-mouse-def-cmd-release-path-sends-correct-sequence ()
  "Generated release command (press=nil, literal btn=2) sends the correct SGR sequence.
The release path must produce a lowercase 'm' terminator in SGR mode."
  (eval '(kuro--def-mouse-cmd kuro--test-mouse-release-btn2
           2
           nil
           "Test release command for button 2.")
        t)
  (unwind-protect
      (kuro-input-mouse-test--with-send 1000 t nil 3 4
        (kuro--test-mouse-release-btn2)
        ;; SGR: button=2, col1=4, row1=5, release → ESC[<2;4;5m
        (should (equal sent "\e[<2;4;5m")))
    (unintern 'kuro--test-mouse-release-btn2 obarray)))

(ert-deftest kuro-input-mouse-def-cmd-press-mode0-is-noop ()
  "Generated press command sends nothing when kuro--mouse-mode is 0.
kuro--dispatch-mouse-event guards on (> kuro--mouse-mode 0)."
  (eval '(kuro--def-mouse-cmd kuro--test-mouse-press-noop
           0
           t
           "Test press command that should be a no-op when mode is 0.")
        t)
  (unwind-protect
      (kuro-input-mouse-test--with-send 0 nil nil 0 0
        (kuro--test-mouse-press-noop)
        (should-not sent))
    (unintern 'kuro--test-mouse-press-noop obarray)))

(ert-deftest kuro-input-mouse-def-cmd-x10-release-uses-button3 ()
  "Generated release command in X10 mode (sgr=nil) encodes with button-3 convention.
X10 release always substitutes 3 for the button number (btn-byte = 3+32 = 35)."
  (eval '(kuro--def-mouse-cmd kuro--test-mouse-release-x10
           0
           nil
           "Test release command for X10 mode.")
        t)
  (unwind-protect
      (kuro-input-mouse-test--with-send 1000 nil nil 0 0
        (kuro--test-mouse-release-x10)
        ;; X10 release: btn-byte=35 (3+32), col-byte=33 (1+32), row-byte=33 (1+32)
        (should (equal sent (format "\e[M%c%c%c" 35 33 33))))
    (unintern 'kuro--test-mouse-release-x10 obarray)))

(provide 'kuro-input-mouse-ext2-test)
;;; kuro-input-mouse-ext2-test.el ends here
