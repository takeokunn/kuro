;;; kuro-renderer-pipeline-macros.el --- Macros for Kuro render pipeline  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Macro helpers for the render pipeline.  Keeping them in a sibling module
;; makes the runtime pipeline file read as data flow and control flow instead
;; of macro templates plus execution logic mixed together.

;;; Code:

(defmacro kuro--timed (ms-var &rest body)
  "Execute BODY, store elapsed milliseconds in MS-VAR, return BODY's value.
Uses a private time variable so BODY cannot accidentally shadow it."
  (declare (indent 1))
  `(let ((--timed-start (float-time)))
     (prog1 (progn ,@body)
       (setq ,ms-var (* 1000.0 (- (float-time) --timed-start))))))

(defmacro kuro--with-render-env (&rest body)
  "Execute BODY under render-optimized GC and `inhibit-redisplay' settings.
Sets `gc-cons-threshold' and `gc-cons-percentage' to suppress collection
jitter, then wraps BODY in `inhibit-redisplay' to prevent partial redraws."
  (declare (indent 0))
  `(let* ((gc-cons-threshold kuro--render-gc-threshold)
          (gc-cons-percentage kuro--render-gc-percentage)
          (inhibit-redisplay t))
     ,@body))

(defmacro kuro--reset-cursor-cache ()
  "Clear all cached cursor state so the next render recomputes from scratch.
Must be called after resize, attach, or any operation that invalidates the
cursor's grid position.  The nil values cause `kuro--update-cursor' to skip
the unchanged-state fast path and always query Rust for fresh cursor data."
  `(setq kuro--last-cursor-row     nil
         kuro--last-cursor-col     nil
         kuro--last-cursor-visible nil
         kuro--last-cursor-shape   nil))

(defmacro kuro--with-render-buffer-mutation (&rest body)
  "Execute BODY with bindings required for renderer buffer mutation."
  (declare (indent 0))
  `(let ((inhibit-read-only t)
         (inhibit-modification-hooks t))
     ,@body))

(defmacro kuro--with-update-entry (entry-form row text face-ranges col-to-buf &rest body)
  "Bind flat UPDATE-ENTRY fields from ENTRY-FORM and execute BODY.
ENTRY-FORM is the `[ROW TEXT FACE-RANGES COL-TO-BUF]' vector produced by the
polling pipeline.  Centralizing the layout here keeps `aref' indexing out of
the render logic and makes the data shape explicit at the boundary."
  (declare (indent 5))
  (let ((entry (make-symbol "entry")))
    `(let ((,entry ,entry-form))
       (let ((,row (aref ,entry 0))
             (,text (aref ,entry 1))
             (,face-ranges (aref ,entry 2))
             (,col-to-buf (aref ,entry 3)))
         ,@body))))

(defmacro kuro--do-update-list (update-list row text face-ranges col-to-buf &rest body)
  "Iterate UPDATE-LIST and bind each entry before executing BODY.
Each entry provides ROW, TEXT, FACE-RANGES, and COL-TO-BUF.
The loop shape is shared by the renderer's line-application and face-counting
paths, so this macro keeps the data-shape handling in one place while leaving
the per-entry logic at the call site."
  (declare (indent 5))
  (let ((entries (make-symbol "entries"))
        (index (make-symbol "index")))
    `(let ((,entries ,update-list)
           (,index 0))
       (while (< ,index (length ,entries))
         (kuro--with-update-entry (aref ,entries ,index) ,row ,text ,face-ranges ,col-to-buf
           ,@body)
         (setq ,index (1+ ,index))))))

(defmacro kuro--with-core-render-pipeline-body (&rest body)
  "Run BODY inside the shared core render pipeline envelope.
The envelope handles render-env setup, title refresh, scroll-event
processing, and scroll-indicator updates in one place so the timed and
untimed pipelines can share the same structure."
  `(kuro--with-render-env
     (kuro--apply-title-update)
     (kuro--process-scroll-events)
     ,@body
     (kuro--update-scroll-indicator)))

(defmacro kuro--core-render-pipeline-run (updates-var &rest body)
  "Run BODY inside the shared core render envelope and return UPDATES-VAR."
  (declare (indent 1))
  `(let (,updates-var)
     (kuro--with-core-render-pipeline-body
       ,@body)
     ,updates-var))

(defmacro kuro--core-render-pipeline-run-with-timing
    (updates-var t0-var ffi-ms apply-ms cursor-ms &rest body)
  "Bind UPDATES-VAR, T0-VAR, FFI-MS, APPLY-MS, and CURSOR-MS, then run BODY."
  (declare (indent 5))
  `(let ((,t0-var (float-time))
         ,ffi-ms ,apply-ms ,cursor-ms
         ,updates-var)
     (kuro--with-core-render-pipeline-body
       ,@body)
     (setq kuro--perf-frame-count (1+ kuro--perf-frame-count))
     (kuro--when-divisible kuro--perf-frame-count kuro--perf-sample-interval
       (let ((total-ms   (* 1000.0 (- (float-time) ,t0-var)))
             (face-count (let ((total 0))
                           (kuro--do-update-list ,updates-var _row _text face-ranges _col-to-buf
                             (setq total (+ total (/ (length face-ranges) 6))))
                           total)))
         (kuro--perf-report ,ffi-ms ,apply-ms ,cursor-ms total-ms
                            (length ,updates-var) face-count)))
     ,updates-var))

(provide 'kuro-renderer-pipeline-macros)

;;; kuro-renderer-pipeline-macros.el ends here
