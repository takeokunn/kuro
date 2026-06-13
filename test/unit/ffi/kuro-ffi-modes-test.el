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

;;; Helper macros

(defmacro kuro-ffi-modes-test--with-stub (fn-name return-val &rest body)
  "Run BODY with FN-NAME temporarily returning RETURN-VAL.
Binds `kuro--initialized' to t so the `kuro--call' guard is satisfied."
  (declare (indent 2))
  `(let ((kuro--initialized t))
     (cl-letf (((symbol-function ,fn-name) (lambda (_id) ,return-val)))
       ,@body)))

(defconst kuro-ffi-modes-test--boolean-getter-table
  '((kuro--get-cursor-visible    kuro-core-get-cursor-visible)
    (kuro--get-app-cursor-keys   kuro-core-get-app-cursor-keys)
    (kuro--get-app-keypad        kuro-core-get-app-keypad)
    (kuro--get-bracketed-paste   kuro-core-get-bracketed-paste)
    (kuro--get-sync-output       kuro-core-get-sync-output)
    (kuro--get-mouse-sgr         kuro-core-get-mouse-sgr)
    (kuro--get-mouse-pixel       kuro-core-get-mouse-pixel)
    (kuro--get-focus-events      kuro-core-get-focus-events))
  "Boolean FFI mode getters: each returns t when active, nil when inactive or uninitialized.
Used by `kuro-ffi-modes-test--def-bool-getter' and the comprehensive invariant test.")

(defmacro kuro-ffi-modes-test--def-bool-getter (wrapper core-fn)
  "Define t-when-active and nil-when-inactive tests for boolean WRAPPER."
  (let* ((bare     (replace-regexp-in-string "^kuro--" "kuro-ffi-modes--" (symbol-name wrapper)))
         (t-name   (intern (format "%s-returns-t-when-active" bare)))
         (nil-name (intern (format "%s-returns-nil-when-inactive" bare))))
    `(progn
       (ert-deftest ,t-name ()
         ,(format "%s returns t when the stub returns t." wrapper)
         (kuro-ffi-modes-test--with-stub ',core-fn t
           (should (eq t (,wrapper)))))
       (ert-deftest ,nil-name ()
         ,(format "%s returns nil when the stub returns nil." wrapper)
         (kuro-ffi-modes-test--with-stub ',core-fn nil
           (should (null (,wrapper))))))))

;;; Group 1: Cursor queries

(kuro-ffi-modes-test--def-bool-getter kuro--get-cursor-visible kuro-core-get-cursor-visible)

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

(kuro-ffi-modes-test--def-bool-getter kuro--get-app-cursor-keys kuro-core-get-app-cursor-keys)
(kuro-ffi-modes-test--def-bool-getter kuro--get-app-keypad      kuro-core-get-app-keypad)
(kuro-ffi-modes-test--def-bool-getter kuro--get-bracketed-paste kuro-core-get-bracketed-paste)
(kuro-ffi-modes-test--def-bool-getter kuro--get-sync-output     kuro-core-get-sync-output)

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

(kuro-ffi-modes-test--def-bool-getter kuro--get-mouse-sgr   kuro-core-get-mouse-sgr)
(kuro-ffi-modes-test--def-bool-getter kuro--get-mouse-pixel kuro-core-get-mouse-pixel)

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

(kuro-ffi-modes-test--def-bool-getter kuro--get-focus-events kuro-core-get-focus-events)

(ert-deftest kuro-ffi-modes--all-boolean-getters-return-t-when-active ()
  "Every boolean getter in `kuro-ffi-modes-test--boolean-getter-table' returns t when active."
  (dolist (entry kuro-ffi-modes-test--boolean-getter-table)
    (let ((wrapper (car entry))
          (core-fn (cadr entry)))
      (let ((kuro--initialized t))
        (cl-letf (((symbol-function core-fn) (lambda (_id) t)))
          (should (eq t (funcall wrapper))))))))

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

;;; Groups 7+10: kuro--session-id passthrough (individual and consolidated getters)
;;
;; Each wrapper must pass kuro--session-id (not a hardcoded literal 0) to its
;; core function.  Tests bind kuro--session-id to a distinctive integer and
;; verify the first argument received by the stub matches.

(defconst kuro-ffi-modes-test--session-id-forward-table
  '((kuro-ffi-modes--get-cursor-visible-forwards-session-id
     kuro--get-cursor-visible   kuro-core-get-cursor-visible    42  t)
    (kuro-ffi-modes--get-mouse-mode-forwards-session-id
     kuro--get-mouse-mode       kuro-core-get-mouse-mode        99  1000)
    (kuro-ffi-modes--get-keyboard-flags-forwards-session-id
     kuro--get-keyboard-flags   kuro-core-get-keyboard-flags     5  31)
    (kuro-ffi-modes--get-cursor-state-forwards-session-id
     kuro--get-cursor-state     kuro-core-get-cursor-state     123  (0 0 t 0))
    (kuro-ffi-modes--get-terminal-modes-forwards-session-id
     kuro--get-terminal-modes   kuro-core-get-terminal-modes   456  (nil nil 0 nil nil nil 0)))
  "Table of (test-name wrapper-fn core-fn sid stub-return) for session-id forwarding.")

(defmacro kuro-ffi-modes-test--def-session-id-forward (test-name wrapper-fn core-fn sid stub-return)
  `(ert-deftest ,test-name ()
     ,(format "`%s' passes kuro--session-id to the FFI function." wrapper-fn)
     (let ((kuro--initialized t)
           (kuro--session-id ,sid)
           (captured-sid nil))
       (cl-letf (((symbol-function ',core-fn)
                  (lambda (s) (setq captured-sid s) ,stub-return)))
         (,wrapper-fn)
         (should (= captured-sid ,sid))))))

(kuro-ffi-modes-test--def-session-id-forward kuro-ffi-modes--get-cursor-visible-forwards-session-id    kuro--get-cursor-visible   kuro-core-get-cursor-visible    42  t)
(kuro-ffi-modes-test--def-session-id-forward kuro-ffi-modes--get-mouse-mode-forwards-session-id        kuro--get-mouse-mode       kuro-core-get-mouse-mode        99  1000)
(kuro-ffi-modes-test--def-session-id-forward kuro-ffi-modes--get-keyboard-flags-forwards-session-id    kuro--get-keyboard-flags   kuro-core-get-keyboard-flags     5  31)
(kuro-ffi-modes-test--def-session-id-forward kuro-ffi-modes--get-cursor-state-forwards-session-id      kuro--get-cursor-state     kuro-core-get-cursor-state     123  '(0 0 t 0))
(kuro-ffi-modes-test--def-session-id-forward kuro-ffi-modes--get-terminal-modes-forwards-session-id    kuro--get-terminal-modes   kuro-core-get-terminal-modes   456  '(nil nil 0 nil nil nil 0))

(ert-deftest kuro-ffi-modes-test--all-session-id-forwards-correct ()
  "Every entry in `kuro-ffi-modes-test--session-id-forward-table' forwards session-id correctly."
  (dolist (entry kuro-ffi-modes-test--session-id-forward-table)
    (pcase-let ((`(,_name ,wrapper-fn ,core-fn ,sid ,stub-return) entry))
      (let ((kuro--initialized t)
            (kuro--session-id sid)
            (captured-sid nil))
        (cl-letf (((symbol-function core-fn)
                   (lambda (s) (setq captured-sid s) stub-return)))
          (funcall wrapper-fn)
          (should (= captured-sid sid)))))))

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


(provide 'kuro-ffi-modes-test)
;;; kuro-ffi-modes-test.el ends here
