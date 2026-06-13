;;; kuro-input-keymap-test.el --- Tests for kuro-input-keymap.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; ERT tests for kuro-input-keymap.el keymap construction and table contents.
;; These tests exercise:
;;   - kuro--ctrl-key-table structure and spot-check values
;;   - kuro--xterm-modifier-codes table structure
;;   - kuro--xterm-arrow-codes table structure
;;   - kuro--build-keymap result (keymapp, special/ctrl/meta/nav bindings)
;;   - kuro--send-meta-backspace sequence
;;   - Modifier+arrow xterm CSI sequences produced by the keymap
;;   - yank / yank-pop / clipboard-yank remap assertions (Group 6)
;;
;; Pure Elisp tests — no Rust dynamic module required.
;; All FFI dependencies are stubbed before requiring the module.
;;
;; NOTE: kuro-input-test.el already covers individual Ctrl+letter and
;; Meta+letter binding checks exhaustively.  This file focuses on the
;; structural properties of the tables and the keymap builder itself
;; to avoid duplication.

;;; Code:

(require 'kuro-input-keymap-test-support)


;;; Group 1: kuro--ctrl-key-table structure

(ert-deftest kuro-input-keymap-ctrl-table-has-23-entries ()
  "kuro--ctrl-key-table contains exactly 23 entries.
C-c is intentionally absent (reserved as prefix key).
C-v is absent (handled by scroll-aware `kuro--scroll-aware-ctrl-v')."
  (should (= (length kuro--ctrl-key-table) 23)))

(ert-deftest kuro-input-keymap-ctrl-table-entries-are-cons-pairs ()
  "Every entry in kuro--ctrl-key-table is a (STRING . INTEGER) cons pair."
  (dolist (entry kuro--ctrl-key-table)
    (should (consp entry))
    (should (stringp (car entry)))
    (should (integerp (cdr entry)))))

(ert-deftest kuro-input-keymap-ctrl-table-bytes-in-range ()
  "Every control byte in kuro--ctrl-key-table is in the range 1–31 (ASCII ctrl range)."
  (dolist (entry kuro--ctrl-key-table)
    (let ((byte (cdr entry)))
      (should (>= byte 1))
      (should (<= byte 31)))))

(ert-deftest kuro-input-keymap-ctrl-table-no-c-c ()
  "kuro--ctrl-key-table does not contain C-c (byte 3, the prefix key)."
  (should-not (assoc "C-c" kuro--ctrl-key-table))
  (should-not (rassq 3 kuro--ctrl-key-table)))

(defconst kuro-input-keymap-test--ctrl-key-spot-table
  '((kuro-input-keymap-ctrl-table-spot-check-c-a          "C-a"  1)
    (kuro-input-keymap-ctrl-table-spot-check-c-z          "C-z"  26)
    (kuro-input-keymap-ctrl-table-spot-check-c-backslash  "C-\\" 28)
    (kuro-input-keymap-ctrl-table-spot-check-c-bracket    "C-]"  29)
    (kuro-input-keymap-ctrl-table-spot-check-c-underscore "C-_"  31))
  "Table of (test-name key-str byte) for kuro--ctrl-key-table spot checks.")

(defmacro kuro-input-keymap-test--def-ctrl-key-spot (test-name key-str byte)
  `(ert-deftest ,test-name ()
     ,(format "kuro--ctrl-key-table: %S → byte %d." key-str byte)
     (should (= (cdr (assoc ,key-str kuro--ctrl-key-table)) ,byte))))

(kuro-input-keymap-test--def-ctrl-key-spot kuro-input-keymap-ctrl-table-spot-check-c-a          "C-a"  1)
(kuro-input-keymap-test--def-ctrl-key-spot kuro-input-keymap-ctrl-table-spot-check-c-z          "C-z"  26)
(kuro-input-keymap-test--def-ctrl-key-spot kuro-input-keymap-ctrl-table-spot-check-c-backslash  "C-\\" 28)
(kuro-input-keymap-test--def-ctrl-key-spot kuro-input-keymap-ctrl-table-spot-check-c-bracket    "C-]"  29)
(kuro-input-keymap-test--def-ctrl-key-spot kuro-input-keymap-ctrl-table-spot-check-c-underscore "C-_"  31)

(ert-deftest kuro-input-keymap-test--all-ctrl-key-spots-correct ()
  "All kuro-input-keymap-test--ctrl-key-spot-table entries map to the correct byte."
  (dolist (entry kuro-input-keymap-test--ctrl-key-spot-table)
    (pcase-let ((`(,_name ,key-str ,byte) entry))
      (should (= (cdr (assoc key-str kuro--ctrl-key-table)) byte)))))

(ert-deftest kuro-input-keymap-ctrl-table-no-duplicate-bytes ()
  "kuro--ctrl-key-table has no duplicate control-byte values."
  (let ((bytes (mapcar #'cdr kuro--ctrl-key-table)))
    (should (= (length bytes) (length (delete-dups (copy-sequence bytes)))))))


;;; Group 2: kuro--xterm-modifier-codes table

(ert-deftest kuro-input-keymap-modifier-codes-has-3-entries ()
  "kuro--xterm-modifier-codes contains exactly 3 entries: S, M, C."
  (should (= (length kuro--xterm-modifier-codes) 3)))

(defconst kuro-input-keymap-test--modifier-codes-table
  '((kuro-input-keymap-modifier-codes-shift-is-2 S 2)
    (kuro-input-keymap-modifier-codes-meta-is-3  M 3)
    (kuro-input-keymap-modifier-codes-ctrl-is-5  C 5))
  "Table of (test-name modifier-sym xterm-code) for kuro--xterm-modifier-codes.")

(defmacro kuro-input-keymap-test--def-modifier-code (test-name sym code)
  `(ert-deftest ,test-name ()
     ,(format "kuro--xterm-modifier-codes: %s → %d." sym code)
     (should (= (cdr (assq ',sym kuro--xterm-modifier-codes)) ,code))))

(kuro-input-keymap-test--def-modifier-code kuro-input-keymap-modifier-codes-shift-is-2 S 2)
(kuro-input-keymap-test--def-modifier-code kuro-input-keymap-modifier-codes-meta-is-3  M 3)
(kuro-input-keymap-test--def-modifier-code kuro-input-keymap-modifier-codes-ctrl-is-5  C 5)

(ert-deftest kuro-input-keymap-test--all-modifier-codes-correct ()
  "All kuro-input-keymap-test--modifier-codes-table entries match kuro--xterm-modifier-codes."
  (dolist (entry kuro-input-keymap-test--modifier-codes-table)
    (pcase-let ((`(,_name ,sym ,code) entry))
      (should (= (cdr (assq sym kuro--xterm-modifier-codes)) code)))))


;;; Group 3: kuro--xterm-arrow-codes table

(ert-deftest kuro-input-keymap-arrow-codes-has-4-entries ()
  "kuro--xterm-arrow-codes contains exactly 4 entries: up, down, right, left."
  (should (= (length kuro--xterm-arrow-codes) 4)))

(defconst kuro-input-keymap-test--arrow-codes-table
  '((kuro-input-keymap-arrow-code-up    up    ?A)
    (kuro-input-keymap-arrow-code-down  down  ?B)
    (kuro-input-keymap-arrow-code-right right ?C)
    (kuro-input-keymap-arrow-code-left  left  ?D))
  "Table of (test-name arrow-sym final-byte) for `kuro--xterm-arrow-codes'.")

(defmacro kuro-input-keymap-test--def-arrow-code (test-name sym byte)
  `(ert-deftest ,test-name ()
     ,(format "kuro--xterm-arrow-codes: %s → ?%c." sym byte)
     (should (= (cdr (assq ',sym kuro--xterm-arrow-codes)) ,byte))))

(kuro-input-keymap-test--def-arrow-code kuro-input-keymap-arrow-code-up    up    ?A)
(kuro-input-keymap-test--def-arrow-code kuro-input-keymap-arrow-code-down  down  ?B)
(kuro-input-keymap-test--def-arrow-code kuro-input-keymap-arrow-code-right right ?C)
(kuro-input-keymap-test--def-arrow-code kuro-input-keymap-arrow-code-left  left  ?D)

(ert-deftest kuro-input-keymap-arrow-codes-all-correct ()
  "Every entry in `kuro-input-keymap-test--arrow-codes-table' maps to the correct final byte."
  (dolist (entry kuro-input-keymap-test--arrow-codes-table)
    (pcase-let ((`(,_name ,sym ,byte) entry))
      (should (= (cdr (assq sym kuro--xterm-arrow-codes)) byte)))))


;;; Group 4: kuro--build-keymap result
;; kuro-keymap-test--built-map helper is defined in kuro-input-keymap-test-support.el

(ert-deftest kuro-input-keymap-build-returns-keymap ()
  "kuro--build-keymap returns a value satisfying keymapp."
  (should (keymapp (kuro-keymap-test--built-map))))

(ert-deftest kuro-input-keymap-build-stores-in-variable ()
  "kuro--build-keymap stores the result in kuro--keymap."
  (let ((orig kuro--keymap)
        (kuro-keymap-exceptions nil))
    (unwind-protect
        (progn
          (kuro--build-keymap)
          (should (keymapp kuro--keymap)))
      (setq kuro--keymap orig))))

(ert-deftest kuro-input-keymap-build-has-self-insert-remap ()
  "The built keymap remaps self-insert-command."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [remap self-insert-command]))))

(ert-deftest kuro-input-keymap-build-has-return-binding ()
  "[return] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [return]))))

(ert-deftest kuro-input-keymap-build-has-tab-binding ()
  "[tab] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [tab]))))

(ert-deftest kuro-input-keymap-build-has-backspace-binding ()
  "[backspace] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [backspace]))))

(ert-deftest kuro-input-keymap-build-has-escape-binding ()
  "[escape] is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map [escape]))))

(defconst kuro-input-keymap-test--build-key-table
  '((kuro-input-keymap-build-has-up           [up])
    (kuro-input-keymap-build-has-down         [down])
    (kuro-input-keymap-build-has-left         [left])
    (kuro-input-keymap-build-has-right        [right])
    (kuro-input-keymap-build-has-down-mouse-1 [down-mouse-1])
    (kuro-input-keymap-build-has-mouse-1      [mouse-1])
    (kuro-input-keymap-build-has-mouse-4      [mouse-4])
    (kuro-input-keymap-build-has-mouse-5      [mouse-5]))
  "Table of (test-name key) verifying key is bound in the built keymap.")

(defmacro kuro-input-keymap-test--def-build-has-key (test-name key)
  `(ert-deftest ,test-name ()
     ,(format "Built keymap has binding for %S." key)
     (should (lookup-key (kuro-keymap-test--built-map) ,key))))

(kuro-input-keymap-test--def-build-has-key kuro-input-keymap-build-has-up           [up])
(kuro-input-keymap-test--def-build-has-key kuro-input-keymap-build-has-down         [down])
(kuro-input-keymap-test--def-build-has-key kuro-input-keymap-build-has-left         [left])
(kuro-input-keymap-test--def-build-has-key kuro-input-keymap-build-has-right        [right])
(kuro-input-keymap-test--def-build-has-key kuro-input-keymap-build-has-down-mouse-1 [down-mouse-1])
(kuro-input-keymap-test--def-build-has-key kuro-input-keymap-build-has-mouse-1      [mouse-1])
(kuro-input-keymap-test--def-build-has-key kuro-input-keymap-build-has-mouse-4      [mouse-4])
(kuro-input-keymap-test--def-build-has-key kuro-input-keymap-build-has-mouse-5      [mouse-5])

(ert-deftest kuro-input-keymap-build-has-all-arrow-and-mouse-keys ()
  "Every entry in `kuro-input-keymap-test--build-key-table' is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (dolist (entry kuro-input-keymap-test--build-key-table)
      (pcase-let ((`(,_name ,key) entry))
        (should (lookup-key map key))))))

(provide 'kuro-input-keymap-test)

;;; kuro-input-keymap-test.el ends here
