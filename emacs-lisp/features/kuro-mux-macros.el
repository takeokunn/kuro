;;; kuro-mux-macros.el --- Shared macro helpers for kuro-mux  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; Macro helpers shared by the kuro-mux feature modules.
;; Keeping these in a dedicated file makes the byte-compile dependency
;; order explicit and keeps the runtime modules focused on behavior.

;;; Code:

(defmacro kuro--def-mux-nav (name nav-fn docstring)
  "Define NAME as a kuro-mux session cycle command.
DOCSTRING becomes the generated command docstring.
NAV-FN is called with (current-buffer sessions) to pick the target buffer."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let ((sessions (kuro-mux--live-sessions)))
       (cond
        ((null sessions)       (message "kuro-mux: no active sessions"))
        ((null (cdr sessions)) (switch-to-buffer (car sessions)))
        (t                     (switch-to-buffer
                                (,nav-fn (current-buffer) sessions)))))))

(defmacro kuro--def-mux-split (name split-fn docstring)
  "Define NAME as a kuro-mux split command.
DOCSTRING becomes the generated command docstring.
SPLIT-FN is called with no arguments to create the new window."
  `(defun ,name (&optional command)
     ,docstring
     (interactive)
     (let ((win (,split-fn)))
       (select-window win)
       (kuro-create (or command kuro-shell)))))

(defmacro kuro--def-mux-swap (name window-nav-fn docstring)
  "Define NAME as a kuro-mux pane-swap command.
DOCSTRING becomes the generated command docstring.
WINDOW-NAV-FN is called with `selected-window' and the visible flag
to pick the peer."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let ((peer (,window-nav-fn (selected-window) nil 'visible)))
       (if (eq peer (selected-window))
          (user-error "Kuro-mux: only one window visible")
         (window-swap-states (selected-window) peer)))))

(defmacro kuro--mux-resize-dispatch (direction delta)
  "Expand DIRECTION and DELTA into a direct window resize call."
  `(pcase ,direction
     ('up    (enlarge-window ,delta))
     ('down  (shrink-window ,delta))
     ('left  (shrink-window-horizontally ,delta))
     ('right (enlarge-window-horizontally ,delta))
     (_      (user-error "Kuro-mux: invalid direction: %s" ,direction))))

(provide 'kuro-mux-macros)

;;; kuro-mux-macros.el ends here
