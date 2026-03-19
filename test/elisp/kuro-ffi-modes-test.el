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

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub FFI primitives that require the Rust dynamic module.
;; Each stub is only installed if the symbol is not already fboundp
;; (so the real module wins when tests are run in a live Emacs with kuro loaded).

(unless (fboundp 'kuro--call)
  (defmacro kuro--call (default form)
    `(condition-case nil ,form (error ,default))))

(unless (fboundp 'kuro-core-get-cursor-visible)
  (defalias 'kuro-core-get-cursor-visible  (lambda () nil)))
(unless (fboundp 'kuro-core-get-cursor-shape)
  (defalias 'kuro-core-get-cursor-shape    (lambda () nil)))
(unless (fboundp 'kuro-core-get-app-cursor-keys)
  (defalias 'kuro-core-get-app-cursor-keys (lambda () nil)))
(unless (fboundp 'kuro-core-get-app-keypad)
  (defalias 'kuro-core-get-app-keypad      (lambda () nil)))
(unless (fboundp 'kuro-core-get-bracketed-paste)
  (defalias 'kuro-core-get-bracketed-paste (lambda () nil)))
(unless (fboundp 'kuro-core-get-mouse-mode)
  (defalias 'kuro-core-get-mouse-mode      (lambda () nil)))
(unless (fboundp 'kuro-core-get-mouse-sgr)
  (defalias 'kuro-core-get-mouse-sgr       (lambda () nil)))
(unless (fboundp 'kuro-core-get-focus-events)
  (defalias 'kuro-core-get-focus-events    (lambda () nil)))
(unless (fboundp 'kuro-core-get-sync-output)
  (defalias 'kuro-core-get-sync-output     (lambda () nil)))
(unless (fboundp 'kuro-core-get-keyboard-flags)
  (defalias 'kuro-core-get-keyboard-flags  (lambda () nil)))
(unless (fboundp 'kuro-core-get-mouse-pixel)
  (defalias 'kuro-core-get-mouse-pixel     (lambda () nil)))

(require 'kuro-ffi-modes)

;;; Helper macro

(defmacro kuro-ffi-modes-test--with-stub (fn-name return-val &rest body)
  "Run BODY with FN-NAME temporarily returning RETURN-VAL."
  (declare (indent 2))
  `(cl-letf (((symbol-function ,fn-name) (lambda () ,return-val)))
     ,@body))

;;; Group 1: Cursor queries

(ert-deftest kuro-ffi-modes--get-cursor-visible-returns-t-when-stub-returns-t ()
  "kuro--get-cursor-visible returns t when the FFI stub returns t."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-visible t
    (should (eq t (kuro--get-cursor-visible)))))

(ert-deftest kuro-ffi-modes--get-cursor-visible-default-when-stub-returns-nil ()
  "kuro--get-cursor-visible returns t (safe default) when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-visible nil
    ;; The wrapper default is t so the cursor is shown rather than hidden.
    (should (eq t (kuro--get-cursor-visible)))))

(ert-deftest kuro-ffi-modes--get-cursor-shape-returns-integer ()
  "kuro--get-cursor-shape returns an integer (e.g. 2) when the stub does so."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-shape 2
    (should (eq 2 (kuro--get-cursor-shape)))))

(ert-deftest kuro-ffi-modes--get-cursor-shape-default-zero-when-nil ()
  "kuro--get-cursor-shape returns 0 (blinking block) when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-cursor-shape nil
    (should (eq 0 (kuro--get-cursor-shape)))))

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

(ert-deftest kuro-ffi-modes--get-mouse-mode-default-zero-when-nil ()
  "kuro--get-mouse-mode returns 0 (disabled) when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-mouse-mode nil
    (should (eq 0 (kuro--get-mouse-mode)))))

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

(ert-deftest kuro-ffi-modes--get-keyboard-flags-default-zero-when-nil ()
  "kuro--get-keyboard-flags returns 0 when stub returns nil."
  (kuro-ffi-modes-test--with-stub 'kuro-core-get-keyboard-flags nil
    (should (eq 0 (kuro--get-keyboard-flags)))))

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

(provide 'kuro-ffi-modes-test)
;;; kuro-ffi-modes-test.el ends here
