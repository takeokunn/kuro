;;; kuro-ffi-modes-test-2.el --- kuro-ffi-modes tests part 2 — Groups 9, 11-13  -*- lexical-binding: t; -*-

;;; Commentary:
;; Groups 9 (FFI error fallbacks), 11 (terminal-modes field layout),
;; 12 (session-id forwarding), and 13 (nil-default wrappers on FFI error)
;; for kuro-ffi-modes.el.

;;; Code:

(require 'ert)
(require 'cl-lib)

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

(defmacro kuro-ffi-modes-test--with-stub (fn-name return-val &rest body)
  "Run BODY with FN-NAME temporarily returning RETURN-VAL.
Binds `kuro--initialized' to t so the `kuro--call' guard is satisfied."
  (declare (indent 2))
  `(let ((kuro--initialized t))
     (cl-letf (((symbol-function ,fn-name) (lambda (_id) ,return-val)))
       ,@body)))

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

(provide 'kuro-ffi-modes-test-2)
;;; kuro-ffi-modes-test-2.el ends here
