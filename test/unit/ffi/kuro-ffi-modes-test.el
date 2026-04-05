;;; kuro-ffi-modes-test.el --- Tests for kuro-ffi-modes  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-ffi-modes.el DEC mode / cursor / mouse / keyboard query
;; wrappers.  All tests run without the Rust dynamic module: the raw FFI
;; primitives (kuro-core-get-*) are stubbed with defalias before the module
;; under test is loaded.
;;
;; Test strategy:
;;   - Stub returns a truthy value  → wrapper returns the expected type.
;;   - Stub returns nil             → wrapper returns the documented safe default.
;;   - kuro--initialized is toggled to test the guard path.
;;
;; Groups:
;;   Group 1: Cursor queries  (kuro--get-cursor-visible, kuro--get-cursor-shape)
;;   Group 2: DEC mode queries (app-cursor-keys, app-keypad, bracketed-paste,
;;                              sync-output)
;;   Group 3: Mouse queries   (mouse-mode, mouse-sgr, mouse-pixel)
;;   Group 4: Keyboard query  (keyboard-flags, focus-events)
;;   Group 5: kuro--initialized guard path (all wrappers return nil when uninitialized)

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub FFI primitives that require the Rust dynamic module.
;; Each stub is only installed if the symbol is not already fboundp
;; (so the real module wins when tests are run in a live Emacs with kuro loaded).

(unless (fboundp 'kuro-core-get-cursor-state)
  (defalias 'kuro-core-get-cursor-state     (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-terminal-modes)
  (defalias 'kuro-core-get-terminal-modes   (lambda (_id) nil)))

(unless (fboundp 'kuro-core-get-cursor-visible)
  (defalias 'kuro-core-get-cursor-visible  (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-cursor-shape)
  (defalias 'kuro-core-get-cursor-shape    (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-app-cursor-keys)
  (defalias 'kuro-core-get-app-cursor-keys (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-app-keypad)
  (defalias 'kuro-core-get-app-keypad      (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-bracketed-paste)
  (defalias 'kuro-core-get-bracketed-paste (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-mouse-mode)
  (defalias 'kuro-core-get-mouse-mode      (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-mouse-sgr)
  (defalias 'kuro-core-get-mouse-sgr       (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-focus-events)
  (defalias 'kuro-core-get-focus-events    (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-sync-output)
  (defalias 'kuro-core-get-sync-output     (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-keyboard-flags)
  (defalias 'kuro-core-get-keyboard-flags  (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-mouse-pixel)
  (defalias 'kuro-core-get-mouse-pixel     (lambda (_id) nil)))

(require 'kuro-ffi)
(require 'kuro-ffi-modes)

;;; Helper macro

(defmacro kuro-ffi-modes-test--with-stub (fn-name return-val &rest body)
  "Run BODY with FN-NAME temporarily returning RETURN-VAL.
Binds `kuro--initialized' to t so the `kuro--call' guard is satisfied."
  (declare (indent 2))
  `(let ((kuro--initialized t))
     (cl-letf (((symbol-function ,fn-name) (lambda (_id) ,return-val)))
       ,@body)))

;;; Group 1: Cursor queries

(ert-deftest kuro-ffi-modes--get-cursor-visible-returns-t-when-stub-returns-t ()
  "kuro--get-cursor-visible returns t when the FFI stub returns t."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-visible t
    (should (eq t (kuro--get-cursor-visible)))))

(ert-deftest kuro-ffi-modes--get-cursor-visible-nil-when-stub-returns-nil ()
  "kuro--get-cursor-visible returns nil when FFI returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-visible nil
    (should (null (kuro--get-cursor-visible)))))

(ert-deftest kuro-ffi-modes--get-cursor-shape-returns-integer ()
  "kuro--get-cursor-shape returns an integer (e.g. 2) when the stub does so."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-shape 2
    (should (eq 2 (kuro--get-cursor-shape)))))

(ert-deftest kuro-ffi-modes--get-cursor-shape-nil-when-stub-returns-nil ()
  "kuro--get-cursor-shape returns nil when FFI returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-shape nil
    (should (null (kuro--get-cursor-shape)))))

(ert-deftest kuro-ffi-modes--get-cursor-shape-all-valid-values ()
  "kuro--get-cursor-shape passes through all DECSCUSR values 0-6 unchanged."
  (dolist (shape '(0 1 2 3 4 5 6))
    (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-shape shape
      (should (eq shape (kuro--get-cursor-shape))))))

;;; Group 2: DEC mode queries

(ert-deftest kuro-ffi-modes--get-app-cursor-keys-returns-t-when-active ()
  "kuro--get-app-cursor-keys returns t when application cursor keys are enabled."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-app-cursor-keys t
    (should (eq t (kuro--get-app-cursor-keys)))))

(ert-deftest kuro-ffi-modes--get-app-cursor-keys-returns-nil-when-inactive ()
  "kuro--get-app-cursor-keys returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-app-cursor-keys nil
    (should (null (kuro--get-app-cursor-keys)))))

(ert-deftest kuro-ffi-modes--get-app-keypad-returns-t-when-active ()
  "kuro--get-app-keypad returns t when application keypad mode is enabled."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-app-keypad t
    (should (eq t (kuro--get-app-keypad)))))

(ert-deftest kuro-ffi-modes--get-app-keypad-returns-nil-when-inactive ()
  "kuro--get-app-keypad returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-app-keypad nil
    (should (null (kuro--get-app-keypad)))))

(ert-deftest kuro-ffi-modes--get-bracketed-paste-returns-t-when-active ()
  "kuro--get-bracketed-paste returns t when bracketed paste mode is enabled."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-bracketed-paste t
    (should (eq t (kuro--get-bracketed-paste)))))

(ert-deftest kuro-ffi-modes--get-bracketed-paste-returns-nil-when-inactive ()
  "kuro--get-bracketed-paste returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-bracketed-paste nil
    (should (null (kuro--get-bracketed-paste)))))

(ert-deftest kuro-ffi-modes--get-sync-output-returns-t-when-active ()
  "kuro--get-sync-output returns t when synchronized output is enabled."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-sync-output t
    (should (eq t (kuro--get-sync-output)))))

(ert-deftest kuro-ffi-modes--get-sync-output-returns-nil-when-inactive ()
  "kuro--get-sync-output returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-sync-output nil
    (should (null (kuro--get-sync-output)))))

;;; Group 3: Mouse queries

(ert-deftest kuro-ffi-modes--get-mouse-mode-returns-1000 ()
  "kuro--get-mouse-mode returns 1000 (normal tracking) when stub returns 1000."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-mode 1000
    (should (eq 1000 (kuro--get-mouse-mode)))))

(ert-deftest kuro-ffi-modes--get-mouse-mode-nil-when-stub-returns-nil ()
  "kuro--get-mouse-mode returns nil when FFI returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-mode nil
    (should (null (kuro--get-mouse-mode)))))

(ert-deftest kuro-ffi-modes--get-mouse-mode-values-1002-1003 ()
  "kuro--get-mouse-mode passes through button-event (1002) and any-event (1003)."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-mode 1002
    (should (eq 1002 (kuro--get-mouse-mode))))
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-mode 1003
    (should (eq 1003 (kuro--get-mouse-mode)))))

(ert-deftest kuro-ffi-modes--get-mouse-sgr-returns-t-when-active ()
  "kuro--get-mouse-sgr returns t when SGR mouse mode is enabled."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-sgr t
    (should (eq t (kuro--get-mouse-sgr)))))

(ert-deftest kuro-ffi-modes--get-mouse-sgr-returns-nil-when-inactive ()
  "kuro--get-mouse-sgr returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-sgr nil
    (should (null (kuro--get-mouse-sgr)))))

(ert-deftest kuro-ffi-modes--get-mouse-pixel-returns-t-when-active ()
  "kuro--get-mouse-pixel returns t when pixel coordinate mode is enabled."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-pixel t
    (should (eq t (kuro--get-mouse-pixel)))))

(ert-deftest kuro-ffi-modes--get-mouse-pixel-returns-nil-when-inactive ()
  "kuro--get-mouse-pixel returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-pixel nil
    (should (null (kuro--get-mouse-pixel)))))

;;; Group 4: Keyboard and focus queries

(ert-deftest kuro-ffi-modes--get-keyboard-flags-returns-integer ()
  "kuro--get-keyboard-flags returns an integer bitmask when stub returns one."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-keyboard-flags 7
    (should (eq 7 (kuro--get-keyboard-flags)))))

(ert-deftest kuro-ffi-modes--get-keyboard-flags-nil-when-stub-returns-nil ()
  "kuro--get-keyboard-flags returns nil when FFI returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-keyboard-flags nil
    (should (null (kuro--get-keyboard-flags)))))

(ert-deftest kuro-ffi-modes--get-keyboard-flags-all-bits ()
  "kuro--get-keyboard-flags passes through all 5 defined flag bits."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-keyboard-flags 31
    (should (eq 31 (kuro--get-keyboard-flags)))))

(ert-deftest kuro-ffi-modes--get-focus-events-returns-t-when-active ()
  "kuro--get-focus-events returns t when focus event reporting is enabled."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-focus-events t
    (should (eq t (kuro--get-focus-events)))))

(ert-deftest kuro-ffi-modes--get-focus-events-returns-nil-when-inactive ()
  "kuro--get-focus-events returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-focus-events nil
    (should (null (kuro--get-focus-events)))))

;;; Test helper macro

(defmacro kuro-ffi-modes-test--uninit-nil (sym &rest args)
  "Define an ert-deftest asserting (SYM ARGS...) returns nil when uninit.
SYM must be a kuro-- prefixed symbol; the test is named by stripping that prefix."
  (let* ((bare (replace-regexp-in-string "^kuro--" "" (symbol-name sym)))
         (test-name (intern (format "kuro-ffi-modes--%s-nil-when-not-initialized" bare))))
    `(ert-deftest ,test-name ()
       ,(format "%s returns nil when kuro--initialized is nil." sym)
       (let ((kuro--initialized nil))
         (should (null (,sym ,@args)))))))

;;; Group 5: kuro--initialized guard path
;;
;; When `kuro--initialized' is nil, the `kuro--call' macro's `when' form
;; short-circuits and returns nil — regardless of the declared fallback value.
;; These tests verify that every kuro-ffi-modes wrapper returns nil in that case.

(kuro-ffi-modes-test--uninit-nil kuro--get-cursor-visible)
(kuro-ffi-modes-test--uninit-nil kuro--get-cursor-shape)
(kuro-ffi-modes-test--uninit-nil kuro--get-app-cursor-keys)
(kuro-ffi-modes-test--uninit-nil kuro--get-app-keypad)
(kuro-ffi-modes-test--uninit-nil kuro--get-bracketed-paste)
(kuro-ffi-modes-test--uninit-nil kuro--get-mouse-mode)
(kuro-ffi-modes-test--uninit-nil kuro--get-mouse-sgr)
(kuro-ffi-modes-test--uninit-nil kuro--get-mouse-pixel)
(kuro-ffi-modes-test--uninit-nil kuro--get-focus-events)
(kuro-ffi-modes-test--uninit-nil kuro--get-sync-output)
(kuro-ffi-modes-test--uninit-nil kuro--get-keyboard-flags)

;;; Group 6: Consolidated queries (kuro--get-cursor-state, kuro--get-terminal-modes)

(ert-deftest kuro-ffi-modes--get-cursor-state-returns-list ()
  "kuro--get-cursor-state returns a (ROW COL VISIBLE SHAPE) list from the stub."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-state '(5 10 t 2)
    (let ((result (kuro--get-cursor-state)))
      (should (listp result))
      (should (= (nth 0 result) 5))
      (should (= (nth 1 result) 10))
      (should (eq (nth 2 result) t))
      (should (= (nth 3 result) 2)))))

(ert-deftest kuro-ffi-modes--get-cursor-state-nil-when-stub-returns-nil ()
  "kuro--get-cursor-state returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-state nil
    (should (null (kuro--get-cursor-state)))))

(kuro-ffi-modes-test--uninit-nil kuro--get-cursor-state)

(ert-deftest kuro-ffi-modes--get-terminal-modes-returns-list ()
  "kuro--get-terminal-modes returns the full modes list from the stub."
  (let ((expected '(t nil 1000 nil nil t 0)))
    (kuro-ffi-modes-test--with-stub 'kuro-core-get-terminal-modes expected
      (let ((result (kuro--get-terminal-modes)))
        (should (equal result expected))))))

(ert-deftest kuro-ffi-modes--get-terminal-modes-nil-when-stub-returns-nil ()
  "kuro--get-terminal-modes returns nil when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-terminal-modes nil
    (should (null (kuro--get-terminal-modes)))))

(kuro-ffi-modes-test--uninit-nil kuro--get-terminal-modes)

;;; Group 7: kuro--session-id passthrough
;;
;; Each wrapper must pass kuro--session-id (not a hardcoded literal 0) to its
;; core function.  Tests bind kuro--session-id to a distinctive integer and
;; verify the first argument received by the stub matches.

(ert-deftest kuro-ffi-modes--get-cursor-visible-forwards-session-id ()
  "kuro--get-cursor-visible passes kuro--session-id to the FFI function."
  (let ((kuro--initialized t)
        (kuro--session-id 42)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-cursor-visible)
               (lambda (sid) (setq captured-sid sid) t)))
      (kuro--get-cursor-visible)
      (should (= captured-sid 42)))))

(ert-deftest kuro-ffi-modes--get-mouse-mode-forwards-session-id ()
  "kuro--get-mouse-mode passes kuro--session-id to the FFI function."
  (let ((kuro--initialized t)
        (kuro--session-id 99)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-mouse-mode)
               (lambda (sid) (setq captured-sid sid) 1000)))
      (kuro--get-mouse-mode)
      (should (= captured-sid 99)))))

(ert-deftest kuro-ffi-modes--get-keyboard-flags-forwards-session-id ()
  "kuro--get-keyboard-flags passes kuro--session-id to the FFI function."
  (let ((kuro--initialized t)
        (kuro--session-id 5)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-keyboard-flags)
               (lambda (sid) (setq captured-sid sid) 31)))
      (kuro--get-keyboard-flags)
      (should (= captured-sid 5)))))

;;; Group 8: kuro--define-ffi-getters macro — docstring accessibility

(ert-deftest kuro-ffi-modes--get-cursor-visible-has-docstring ()
  "kuro--get-cursor-visible has an accessible docstring (macro expansion works)."
  (let ((doc (documentation 'kuro--get-cursor-visible)))
    (should (stringp doc))
    (should (> (length doc) 0))))

(ert-deftest kuro-ffi-modes--get-mouse-mode-has-docstring ()
  "kuro--get-mouse-mode has an accessible docstring generated by the macro."
  (let ((doc (documentation 'kuro--get-mouse-mode)))
    (should (stringp doc))
    (should (string-match-p "mouse" (downcase doc)))))

(ert-deftest kuro-ffi-modes--get-keyboard-flags-has-docstring ()
  "kuro--get-keyboard-flags has an accessible docstring generated by the macro."
  (let ((doc (documentation 'kuro--get-keyboard-flags)))
    (should (stringp doc))
    (should (string-match-p "keyboard\\|kitty\\|bitmask" (downcase doc)))))

(ert-deftest kuro-ffi-modes--get-terminal-modes-has-docstring ()
  "kuro--get-terminal-modes has an accessible docstring generated by the macro."
  (let ((doc (documentation 'kuro--get-terminal-modes)))
    (should (stringp doc))
    (should (> (length doc) 0))))

;;; Group 9: Fallback values on FFI error
;;
;; Three wrappers have a non-nil fallback (t or 0) declared via kuro--def-ffi-getter.
;; When kuro--initialized is t but the core function signals an error, kuro--call
;; must return the declared fallback — not nil.

(ert-deftest kuro-ffi-modes--get-cursor-visible-returns-t-fallback-on-ffi-error ()
  "kuro--get-cursor-visible returns t (its declared fallback) on FFI error."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-cursor-visible)
               (lambda (_id) (error "FFI crash"))))
      (should (eq t (kuro--get-cursor-visible))))))

(ert-deftest kuro-ffi-modes--get-cursor-shape-returns-zero-fallback-on-ffi-error ()
  "kuro--get-cursor-shape returns 0 (its declared fallback) on FFI error."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-cursor-shape)
               (lambda (_id) (error "FFI crash"))))
      (should (= 0 (kuro--get-cursor-shape))))))

(ert-deftest kuro-ffi-modes--get-mouse-mode-returns-zero-fallback-on-ffi-error ()
  "kuro--get-mouse-mode returns 0 (its declared fallback) on FFI error."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-mouse-mode)
               (lambda (_id) (error "FFI crash"))))
      (should (= 0 (kuro--get-mouse-mode))))))

(ert-deftest kuro-ffi-modes--get-keyboard-flags-returns-zero-fallback-on-ffi-error ()
  "kuro--get-keyboard-flags returns 0 (its declared fallback) on FFI error."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-keyboard-flags)
               (lambda (_id) (error "FFI crash"))))
      (should (= 0 (kuro--get-keyboard-flags))))))

;;; Group 10: kuro--session-id forwarding for consolidated queries

(ert-deftest kuro-ffi-modes--get-cursor-state-forwards-session-id ()
  "kuro--get-cursor-state passes kuro--session-id as first arg to the core fn."
  (let ((kuro--initialized t)
        (kuro--session-id 123)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-cursor-state)
               (lambda (sid) (setq captured-sid sid) '(0 0 t 0))))
      (kuro--get-cursor-state)
      (should (= captured-sid 123)))))

(ert-deftest kuro-ffi-modes--get-terminal-modes-forwards-session-id ()
  "kuro--get-terminal-modes passes kuro--session-id as first arg to the core fn."
  (let ((kuro--initialized t)
        (kuro--session-id 456)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-terminal-modes)
               (lambda (sid) (setq captured-sid sid) '(nil nil 0 nil nil nil 0))))
      (kuro--get-terminal-modes)
      (should (= captured-sid 456)))))

;;; Group 11: kuro--get-terminal-modes field layout
;;
;; The documented return is (APP-CURSOR-KEYS APP-KEYPAD MOUSE-MODE MOUSE-SGR
;; MOUSE-PIXEL BRACKETED-PASTE KEYBOARD-FLAGS).  Verify callers can rely on
;; the positional layout of each field.

(ert-deftest kuro-ffi-modes--get-terminal-modes-field-layout ()
  "kuro--get-terminal-modes result fields match documented order."
  (let ((modes '(t nil 1002 t t nil 4)))
    (kuro-ffi-modes-test--with-stub 'kuro-core-get-terminal-modes modes
      (let ((result (kuro--get-terminal-modes)))
        (should (eq   (nth 0 result) t))     ; app-cursor-keys
        (should (null (nth 1 result)))        ; app-keypad
        (should (= (nth 2 result) 1002))      ; mouse-mode
        (should (eq   (nth 3 result) t))      ; mouse-sgr
        (should (eq   (nth 4 result) t))      ; mouse-pixel
        (should (null (nth 5 result)))        ; bracketed-paste
        (should (= (nth 6 result) 4))))))     ; keyboard-flags

;;; Group 12: session-id forwarding for boolean getters
;;
;; Groups 7 and 10 covered a selection of wrappers.  This group completes the
;; picture: every remaining getter must forward kuro--session-id, not a literal.

(defmacro kuro-ffi-modes-test--session-id-fwd (wrapper core-fn sid stub-val)
  "Define an ert-deftest asserting WRAPPER forwards SESSION-ID to CORE-FN.
STUB-VAL is the value the stub returns so the call succeeds."
  (let* ((bare (replace-regexp-in-string "^kuro--" "" (symbol-name wrapper)))
         (test-name (intern (format "kuro-ffi-modes--%s-forwards-session-id" bare))))
    `(ert-deftest ,test-name ()
       ,(format "%s passes kuro--session-id to the FFI function." wrapper)
       (let ((kuro--initialized t)
             (kuro--session-id ,sid)
             (captured-sid nil))
         (cl-letf (((symbol-function ',core-fn)
                    (lambda (s) (setq captured-sid s) ,stub-val)))
           (,wrapper)
           (should (= captured-sid ,sid)))))))

(kuro-ffi-modes-test--session-id-fwd kuro--get-cursor-shape    kuro-core-get-cursor-shape    10 2)
(kuro-ffi-modes-test--session-id-fwd kuro--get-app-cursor-keys kuro-core-get-app-cursor-keys 20 t)
(kuro-ffi-modes-test--session-id-fwd kuro--get-app-keypad      kuro-core-get-app-keypad      30 t)
(kuro-ffi-modes-test--session-id-fwd kuro--get-bracketed-paste kuro-core-get-bracketed-paste 40 t)
(kuro-ffi-modes-test--session-id-fwd kuro--get-mouse-sgr       kuro-core-get-mouse-sgr       50 t)
(kuro-ffi-modes-test--session-id-fwd kuro--get-mouse-pixel     kuro-core-get-mouse-pixel     60 t)
(kuro-ffi-modes-test--session-id-fwd kuro--get-focus-events    kuro-core-get-focus-events    70 t)
(kuro-ffi-modes-test--session-id-fwd kuro--get-sync-output     kuro-core-get-sync-output     80 t)

;;; Group 13: nil-default wrappers return nil on FFI error, not the fallback
;;
;; Wrappers with DEFAULT=nil (app-cursor-keys, bracketed-paste, mouse-sgr,
;; mouse-pixel, focus-events, sync-output, app-keypad) must return nil when
;; kuro--call catches an error — since nil is both the fallback and the safe
;; sentinel.  This group makes the error path explicit for each such wrapper.

(defmacro kuro-ffi-modes-test--nil-on-ffi-error (wrapper core-fn)
  "Define an ert-deftest asserting WRAPPER returns nil when CORE-FN signals an error."
  (let* ((bare (replace-regexp-in-string "^kuro--" "" (symbol-name wrapper)))
         (test-name (intern (format "kuro-ffi-modes--%s-nil-on-ffi-error" bare))))
    `(ert-deftest ,test-name ()
       ,(format "%s returns nil when the FFI function signals an error." wrapper)
       (let ((kuro--initialized t))
         (cl-letf (((symbol-function ',core-fn)
                    (lambda (_id) (error "FFI crash"))))
           (should (null (,wrapper))))))))

(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-app-cursor-keys kuro-core-get-app-cursor-keys)
(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-app-keypad      kuro-core-get-app-keypad)
(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-bracketed-paste kuro-core-get-bracketed-paste)
(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-mouse-sgr       kuro-core-get-mouse-sgr)
(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-focus-events    kuro-core-get-focus-events)
(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-sync-output     kuro-core-get-sync-output)
(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-mouse-pixel     kuro-core-get-mouse-pixel)
(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-cursor-state    kuro-core-get-cursor-state)
(kuro-ffi-modes-test--nil-on-ffi-error kuro--get-terminal-modes  kuro-core-get-terminal-modes)

(ert-deftest kuro-ffi-modes--get-terminal-modes-keyboard-flags-bitmask-values ()
  "kuro--get-terminal-modes passes through each single-bit keyboard-flags value."
  (dolist (flags '(1 2 4 8 16))
    (let ((modes (list nil nil 0 nil nil nil flags)))
      (kuro-ffi-modes-test--with-stub 'kuro-core-get-terminal-modes modes
        (let ((result (kuro--get-terminal-modes)))
          (should (= (nth 6 result) flags)))))))

(ert-deftest kuro-ffi-modes--get-cursor-state-shape-range ()
  "kuro--get-cursor-state passes through cursor shapes 0-6 in position 3."
  (dolist (shape '(0 1 2 3 4 5 6))
    (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-state (list 0 0 t shape)
      (let ((result (kuro--get-cursor-state)))
        (should (= (nth 3 result) shape))))))

(provide 'kuro-ffi-modes-test)
;;; kuro-ffi-modes-test.el ends here
