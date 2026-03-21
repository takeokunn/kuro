;;; kuro-faces.el --- Color conversion and face management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides face caching, face application, and OSC color update
;; handling for the Kuro terminal emulator.
;;
;; # Responsibilities
;;
;; - Per-session face cache (avoids recreating identical faces each render frame)
;; - Font remapping for per-buffer font family/size overrides
;; - Raw FFI integer face cache lookup via `kuro--get-cached-face-raw'
;; - OSC 10/11/12 default color application (foreground/background/cursor)
;; - OSC 4 palette update application via `kuro--apply-palette-updates'
;;   (reads index/RGB triples from Rust core, updates `kuro--named-colors',
;;   and clears the face cache so new colors take effect on the next render)
;;
;; # Dependencies
;;
;; Depends on `kuro-config' for `kuro-font-family' and `kuro-font-size'.
;; Depends on `kuro-ffi' for `kuro--initialized' and OSC query functions.
;; Depends on `kuro-ffi-osc' for `kuro--get-default-colors' and
;; `kuro--get-palette-updates'.
;; Depends on `kuro-faces-color' for `kuro--decode-ffi-color', `kuro--rgb-to-emacs',
;; `kuro--color-to-emacs', and `kuro--ansi-color-names'.
;; Depends on `kuro-faces-attrs' for `kuro--attrs-to-face-props'.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-ffi-osc)
(require 'kuro-faces-color)
(require 'kuro-faces-attrs)

;; Core Emacs face remapping functions (provided by C core; suppress warnings)
(declare-function face-remap-remove-relative "face-remap" (cookie))

;; Cross-module function declarations for byte-compile hygiene
(declare-function kuro--get-default-colors  "kuro-ffi-osc" ())
(declare-function kuro--get-palette-updates "kuro-ffi-osc" ())
(declare-function kuro--decode-ffi-color    "kuro-faces-color" (color-enc))
(declare-function kuro--rgb-to-emacs        "kuro-faces-color" (rgb-value))
(declare-function kuro--color-to-emacs      "kuro-faces-color" (color))
(declare-function kuro--attrs-to-face-props "kuro-faces-attrs" (fg bg attr-flags underline-color))

(defconst kuro--face-cache-max-size 4096
  "Maximum number of entries in the face cache before flushing.")

;;; Face cache

(defvar kuro--face-cache (make-hash-table :test 'equal)
  "Cache computed faces to avoid recreating them for same attribute combinations.")

(defvar-local kuro--font-remap-cookie nil
  "Cookie returned by `face-remap-add-relative' for font customization.
Stored per-buffer so the remap can be cleanly removed when settings change
or when the buffer is killed.  Internal state; do not set directly.")
(put 'kuro--font-remap-cookie 'permanent-local t)

(defvar-local kuro--face-cache-lookup-key (vector 0 0 0 0)
  "Pre-allocated vector for face cache lookup, mutated in-place by
`kuro--get-cached-face-raw' to avoid one cons allocation per cache hit.
A fresh vector is created only on cache miss (when puthash is called),
so the stored key is never the same object as this lookup vector.")
(put 'kuro--face-cache-lookup-key 'permanent-local t)

;;; Font remapping

(defun kuro--apply-font-to-buffer (buf)
  "Apply `kuro-font-family' and `kuro-font-size' settings to BUF.
Uses `face-remap-add-relative' to override the default face in the buffer.
Removes any previously installed remap cookie before applying a new one.
This function is a no-op in non-graphical (terminal) Emacs frames."
  (when (display-graphic-p)
    (with-current-buffer buf
      (when kuro--font-remap-cookie
        (face-remap-remove-relative kuro--font-remap-cookie)
        (setq kuro--font-remap-cookie nil))
      (when (or kuro-font-family kuro-font-size)
        (setq kuro--font-remap-cookie
              (apply #'face-remap-add-relative
                     'default
                     (append
                      (when kuro-font-family (list :family kuro-font-family))
                      (when kuro-font-size   (list :height (* 10 kuro-font-size))))))))))

;;; Face caching

(defun kuro--make-face (fg bg flags underline-color)
  "Create an Emacs face spec from decoded FG, BG, FLAGS, and UNDERLINE-COLOR."
  (kuro--attrs-to-face-props fg bg flags underline-color))

(defun kuro--get-cached-face-raw (fg-enc bg-enc flags ul-enc)
  "Get or create a cached face using raw FFI-encoded integer values.
Uses a vector key of raw integers, which avoids cons-cell list allocation
on cache hits and skips color decoding entirely when cached.
FG-ENC, BG-ENC, UL-ENC are u32 FFI color values; FLAGS is a u64 bitmask.
On cache miss, decodes all values and delegates to `kuro--make-face'.

The pre-allocated `kuro--face-cache-lookup-key' vector is mutated in-place
for the gethash call (avoiding one cons per call).  On cache miss a new
vector is created for puthash so stored keys are stable across future calls."
  ;; Normalize ul-enc: both 0 and #xFF000000 mean "no underline color".
  ;; Canonicalizing to 0 prevents duplicate cache entries for the common case.
  (let ((ul-normalized (if (or (null ul-enc)
                               (= ul-enc 0)
                               (= ul-enc #xFF000000))
                           0 ul-enc)))
    ;; Mutate the pre-allocated key vector in-place; no cons on cache hits.
    (aset kuro--face-cache-lookup-key 0 fg-enc)
    (aset kuro--face-cache-lookup-key 1 bg-enc)
    (aset kuro--face-cache-lookup-key 2 flags)
    (aset kuro--face-cache-lookup-key 3 ul-normalized)
    (or (gethash kuro--face-cache-lookup-key kuro--face-cache)
        (progn
          (when (> (hash-table-count kuro--face-cache) kuro--face-cache-max-size)
            (clrhash kuro--face-cache))
          (let* ((fg (kuro--decode-ffi-color fg-enc))
                 (bg (kuro--decode-ffi-color bg-enc))
                 (ul-color (when (/= ul-normalized 0)
                             (kuro--rgb-to-emacs (logand ul-enc kuro--color-rgb-mask))))
                 (face (kuro--make-face fg bg flags ul-color)))
            ;; Store a fresh vector as the cache key so the lookup key can be
            ;; mutated next call without corrupting the stored hash entry.
            (puthash (vector fg-enc bg-enc flags ul-normalized)
                     face kuro--face-cache))))))

(defsubst kuro--clear-face-cache ()
  "Clear the face cache to free memory."
  (clrhash kuro--face-cache))

;;; Default color remapping (OSC 10/11/12)

(defvar-local kuro--default-color-remap-cookie nil
  "Cookie from `face-remap-add-relative' for OSC 10/11/12 default color overrides.
Stored per-buffer so the previous remap is removed before a new one is applied,
preventing stacked face-remap layers from accumulating across OSC color events.")
(put 'kuro--default-color-remap-cookie 'permanent-local t)

(defun kuro--apply-default-colors ()
  "Apply OSC 10/11/12 default terminal colors to the current kuro buffer.
Reads pending color changes from the Rust core and sets buffer-local
`default' face overrides so the terminal background/foreground match
what the running application requested."
  (when kuro--initialized
    (let ((colors (kuro--get-default-colors)))
      (when colors
        (let* ((fg-enc (car colors))
               (bg-enc (cadr colors))
               ;; cursor-enc = (caddr colors) -- future use
               (fg (kuro--decode-ffi-color fg-enc))
               (bg (kuro--decode-ffi-color bg-enc))
               (fg-str (kuro--color-to-emacs fg))
               (bg-str (kuro--color-to-emacs bg)))
          ;; Apply as buffer-local face remapping.
          ;; Remove the previous cookie first so OSC 10/11/12 events do not
          ;; stack: without removal each call adds a new remap layer on top
          ;; of the last, causing compounding color overrides.
          (when (display-graphic-p)
            (when kuro--default-color-remap-cookie
              (face-remap-remove-relative kuro--default-color-remap-cookie)
              (setq kuro--default-color-remap-cookie nil))
            (when (or fg-str bg-str)
              (setq kuro--default-color-remap-cookie
                    (apply #'face-remap-add-relative
                           'default
                           (append
                            (when fg-str (list :foreground fg-str))
                            (when bg-str (list :background bg-str))))))))))))

;;; Palette application (OSC 4)

(defun kuro--apply-palette-updates ()
  "Apply OSC 4 palette overrides from the Rust core.
Updates `kuro--named-colors' entries for indices 0-15 if overridden."
  (when kuro--initialized
    (let ((updates (kuro--get-palette-updates)))
      (dolist (entry updates)
        (let* ((idx  (nth 0 entry))
               (r    (nth 1 entry))
               (g    (nth 2 entry))
               (b    (nth 3 entry))
               (hex  (format "#%02x%02x%02x" r g b)))
          ;; Update named-colors for indices 0-15
          (when (< idx 16)
            (let ((name (aref kuro--ansi-color-names idx)))
              (puthash name hex kuro--named-colors)
              ;; Clear face cache since colors changed
              (kuro--clear-face-cache))))))))

(provide 'kuro-faces)

;;; kuro-faces.el ends here
