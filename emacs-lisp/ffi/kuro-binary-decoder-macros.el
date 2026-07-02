;;; kuro-binary-decoder-macros.el --- Macros for binary frame decoding  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:
;; Macro helpers for binary frame decoding.

;;; Code:

(defmacro kuro--decode-face-range-step (result vec pos base ul-p)
  "Decode one face-range slot from VEC into RESULT; advance BASE and POS.
RESULT, VEC, POS, BASE are symbols bound in the enclosing `while' scope.
UL-P is a compile-time literal: non-nil for v2 (28-byte stride, ul-color
present at wire offset +24); nil for v1 (24-byte stride, ul-color absent —
the slot is 0 from `make-vector').
Specializing at compile time avoids a runtime branch inside the 3,600+/sec
hot decode loop."
  (declare (indent 0))
  (if ul-p
      (let ((b1 (make-symbol "b1")) (b2 (make-symbol "b2"))
            (b3 (make-symbol "b3")) (b4 (make-symbol "b4"))
            (b5 (make-symbol "b5"))
            (p4 (make-symbol "p4"))  (p8 (make-symbol "p8"))
            (p12 (make-symbol "p12")) (p16 (make-symbol "p16"))
            (p24 (make-symbol "p24")))
        `(let* ((,b1  (1+ ,base))
                (,b2  (1+ ,b1))
                (,b3  (1+ ,b2))
                (,b4  (1+ ,b3))
                (,b5  (1+ ,b4))
                (,p4  (+ ,pos  4))
                (,p8  (+ ,p4   4))
                (,p12 (+ ,p8   4))
                (,p16 (+ ,p12  4))
                (,p24 (+ ,p16  8)))
           (aset ,result ,base (kuro--read-u32-le ,vec ,pos))
           (aset ,result ,b1   (kuro--read-u32-le ,vec ,p4))
           (aset ,result ,b2   (kuro--read-u32-le ,vec ,p8))
           (aset ,result ,b3   (kuro--read-u32-le ,vec ,p12))
           ;; Low u32 only — upper 4 bytes are always zero.
           (aset ,result ,b4   (kuro--read-u32-le ,vec ,p16))
           (aset ,result ,b5   (kuro--read-u32-le ,vec ,p24))
           (setq ,base (1+ ,b5))
           (setq ,pos  (+ ,p24 4))))
    (let ((b1 (make-symbol "b1")) (b2 (make-symbol "b2"))
          (b3 (make-symbol "b3")) (b4 (make-symbol "b4"))
          (p4 (make-symbol "p4"))  (p8 (make-symbol "p8"))
          (p12 (make-symbol "p12")) (p16 (make-symbol "p16")))
      `(let* ((,b1  (1+ ,base))
              (,b2  (1+ ,b1))
              (,b3  (1+ ,b2))
              (,b4  (1+ ,b3))
              (,p4  (+ ,pos 4))
              (,p8  (+ ,p4  4))
              (,p12 (+ ,p8  4))
              (,p16 (+ ,p12 4)))
         (aset ,result ,base (kuro--read-u32-le ,vec ,pos))
         (aset ,result ,b1   (kuro--read-u32-le ,vec ,p4))
         (aset ,result ,b2   (kuro--read-u32-le ,vec ,p8))
         (aset ,result ,b3   (kuro--read-u32-le ,vec ,p12))
         ;; Low u32 only — upper 4 bytes are always zero.
         (aset ,result ,b4   (kuro--read-u32-le ,vec ,p16))
         ;; ul-color slot (base+5) stays 0 from make-vector.
         (setq ,base (+ ,base 6))
         (setq ,pos  (+ ,p16 8))))))

(provide 'kuro-binary-decoder-macros)
;;; kuro-binary-decoder-macros.el ends here
