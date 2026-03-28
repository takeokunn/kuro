;;; kuro-ffi-osc-ext-test.el --- Extended unit tests for kuro-ffi-osc.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for kuro-ffi-osc.el (session-id forwarding, value
;; semantics, multi-entry results, and edge cases).
;; Split from kuro-ffi-osc-test.el at Group 4.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'seq)

;; Stub the Rust FFI functions that kuro-ffi-osc.el's (require 'kuro-ffi) would need.
;; These must be defined BEFORE loading kuro-ffi-osc.el.
(unless (fboundp 'kuro-core-get-and-clear-title)
  (fset 'kuro-core-get-and-clear-title (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-cwd)
  (fset 'kuro-core-get-cwd (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-clipboard-actions)
  (fset 'kuro-core-poll-clipboard-actions (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-prompt-marks)
  (fset 'kuro-core-poll-prompt-marks (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-image)
  (fset 'kuro-core-get-image (lambda (_id _img-id) nil)))
(unless (fboundp 'kuro-core-poll-image-notifications)
  (fset 'kuro-core-poll-image-notifications (lambda (_id) nil)))
(unless (fboundp 'kuro-core-consume-scroll-events)
  (fset 'kuro-core-consume-scroll-events (lambda (_id) nil)))
(unless (fboundp 'kuro-core-has-pending-output)
  (fset 'kuro-core-has-pending-output (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-palette-updates)
  (fset 'kuro-core-get-palette-updates (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-default-colors)
  (fset 'kuro-core-get-default-colors (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-scrollback)
  (fset 'kuro-core-get-scrollback (lambda (_id _n) nil)))
(unless (fboundp 'kuro-core-clear-scrollback)
  (fset 'kuro-core-clear-scrollback (lambda (_id) nil)))
(unless (fboundp 'kuro-core-set-scrollback-max-lines)
  (fset 'kuro-core-set-scrollback-max-lines (lambda (_id _n) nil)))
(unless (fboundp 'kuro-core-get-scrollback-count)
  (fset 'kuro-core-get-scrollback-count (lambda (_id) 0)))
(unless (fboundp 'kuro-core-scroll-up)
  (fset 'kuro-core-scroll-up (lambda (_id _n) nil)))
(unless (fboundp 'kuro-core-scroll-down)
  (fset 'kuro-core-scroll-down (lambda (_id _n) nil)))
(unless (fboundp 'kuro-core-get-scroll-offset)
  (fset 'kuro-core-get-scroll-offset (lambda (_id) 0)))

;; Also stub kuro-core-init and other functions required transitively.
(unless (fboundp 'kuro-core-init)
  (fset 'kuro-core-init (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-resize)
  (fset 'kuro-core-resize (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-send-key)
  (fset 'kuro-core-send-key (lambda (&rest _) nil)))
(unless (fboundp 'kuro-core-poll-updates)
  (fset 'kuro-core-poll-updates (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-updates-with-faces)
  (fset 'kuro-core-poll-updates-with-faces (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-cursor)
  (fset 'kuro-core-get-cursor (lambda (_id) nil)))
(unless (fboundp 'kuro-core-is-cursor-visible)
  (fset 'kuro-core-is-cursor-visible (lambda (_id) t)))
(unless (fboundp 'kuro-core-get-cursor-shape)
  (fset 'kuro-core-get-cursor-shape (lambda (_id) 0)))
(unless (fboundp 'kuro-core-get-mouse-tracking-mode)
  (fset 'kuro-core-get-mouse-tracking-mode (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-bracketed-paste)
  (fset 'kuro-core-get-bracketed-paste (lambda (_id) nil)))
(unless (fboundp 'kuro-core-is-alt-screen-active)
  (fset 'kuro-core-is-alt-screen-active (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-focus-tracking)
  (fset 'kuro-core-get-focus-tracking (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-kitty-kb-flags)
  (fset 'kuro-core-get-kitty-kb-flags (lambda (_id) 0)))
(unless (fboundp 'kuro-core-get-sync-update-active)
  (fset 'kuro-core-get-sync-update-active (lambda (_id) nil)))
(unless (fboundp 'kuro-core-shutdown)
  (fset 'kuro-core-shutdown (lambda (_id) nil)))

;; Stub kuro-ffi-modes functions required transitively by kuro-navigation.el.
(unless (fboundp 'kuro-core-get-app-cursor-keys)
  (fset 'kuro-core-get-app-cursor-keys (lambda (_id) nil)))
(unless (fboundp 'kuro-core-get-focus-events)
  (fset 'kuro-core-get-focus-events (lambda (_id) nil)))

;; Stub defcustom variables that kuro-config.el would normally define.
(defvar kuro--initialized nil)

(require 'kuro-ffi-osc)
(require 'kuro-navigation)

;;; Group 4: kuro--session-id forwarding for remaining wrappers
;;
;; Each zero-argument getter passes kuro--session-id as the sole argument to
;; its core function.  Tests bind kuro--session-id to a distinctive integer
;; and verify the stub receives it, catching regressions where a wrapper might
;; inadvertently pass a hardcoded 0.

(ert-deftest kuro-ffi-osc-get-and-clear-title-forwards-session-id ()
  "kuro--get-and-clear-title passes kuro--session-id to kuro-core-get-and-clear-title."
  (let ((kuro--initialized t)
        (kuro--session-id 11)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-and-clear-title)
               (lambda (sid) (setq captured-sid sid) "title")))
      (kuro--get-and-clear-title)
      (should (= captured-sid 11)))))

(ert-deftest kuro-ffi-osc-get-cwd-forwards-session-id ()
  "kuro--get-cwd passes kuro--session-id to kuro-core-get-cwd."
  (let ((kuro--initialized t)
        (kuro--session-id 22)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-cwd)
               (lambda (sid) (setq captured-sid sid) "/tmp")))
      (kuro--get-cwd)
      (should (= captured-sid 22)))))

(ert-deftest kuro-ffi-osc-poll-clipboard-actions-forwards-session-id ()
  "kuro--poll-clipboard-actions passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 33)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-poll-clipboard-actions)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--poll-clipboard-actions)
      (should (= captured-sid 33)))))

(ert-deftest kuro-ffi-osc-poll-prompt-marks-forwards-session-id ()
  "kuro--poll-prompt-marks passes kuro--session-id to kuro-core-poll-prompt-marks."
  (let ((kuro--initialized t)
        (kuro--session-id 44)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-poll-prompt-marks)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--poll-prompt-marks)
      (should (= captured-sid 44)))))

(ert-deftest kuro-ffi-osc-get-image-forwards-session-id ()
  "kuro--get-image passes kuro--session-id as first arg to kuro-core-get-image."
  (let ((kuro--initialized t)
        (kuro--session-id 55)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-image)
               (lambda (sid _image-id) (setq captured-sid sid) nil)))
      (kuro--get-image 1)
      (should (= captured-sid 55)))))

(ert-deftest kuro-ffi-osc-get-palette-updates-forwards-session-id ()
  "kuro--get-palette-updates passes kuro--session-id to kuro-core-get-palette-updates."
  (let ((kuro--initialized t)
        (kuro--session-id 66)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-palette-updates)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--get-palette-updates)
      (should (= captured-sid 66)))))

(ert-deftest kuro-ffi-osc-get-default-colors-forwards-session-id ()
  "kuro--get-default-colors passes kuro--session-id to kuro-core-get-default-colors."
  (let ((kuro--initialized t)
        (kuro--session-id 77)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-default-colors)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--get-default-colors)
      (should (= captured-sid 77)))))

(ert-deftest kuro-ffi-osc-clear-scrollback-forwards-session-id ()
  "kuro--clear-scrollback passes kuro--session-id to kuro-core-clear-scrollback."
  (let ((kuro--initialized t)
        (kuro--session-id 88)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-clear-scrollback)
               (lambda (sid) (setq captured-sid sid) t)))
      (kuro--clear-scrollback)
      (should (= captured-sid 88)))))

;;; Group 5: Zero-vs-nil distinction and edge cases
;;
;; kuro--get-scrollback-count has fallback nil (not 0) but the core may
;; legitimately return 0 when the buffer is empty.  Tests distinguish these
;; two zero-like outcomes.

(ert-deftest kuro-ffi-osc-get-scrollback-count-returns-zero-when-buffer-empty ()
  "kuro--get-scrollback-count returns 0 (not nil) when core returns 0."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback-count)
               (lambda (_id) 0)))
      (should (= 0 (kuro--get-scrollback-count))))))

(ert-deftest kuro-ffi-osc-get-scrollback-count-nil-not-zero-when-uninit ()
  "kuro--get-scrollback-count returns nil (not 0) when kuro--initialized is nil.
The fallback is nil, and kuro--call uses `when', so nil is always returned
when uninitialized — even though 0 would be a valid initialized result."
  (let ((kuro--initialized nil))
    (should (null (kuro--get-scrollback-count)))))

(ert-deftest kuro-ffi-osc-get-image-id-zero-passed-to-core ()
  "kuro--get-image correctly forwards image-id 0 (not treated as falsy)."
  (let ((kuro--initialized t)
        (received-id :not-set))
    (cl-letf (((symbol-function 'kuro-core-get-image)
               (lambda (_sid id) (setq received-id id) nil)))
      (kuro--get-image 0)
      (should (= received-id 0)))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-returns-fallback-zero-on-ffi-error ()
  "kuro--get-scroll-offset returns 0 (the declared fallback) when core errors."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scroll-offset)
               (lambda (_id) (error "scroll error"))))
      (should (= 0 (kuro--get-scroll-offset))))))

;;; Group 6: session-id forwarding for remaining wrappers
;;
;; Groups 3-4 covered scroll-up/down, get-scrollback, and a selection of OSC
;; getters.  This group fills in the remaining wrappers so every function in
;; kuro-ffi-osc.el has at least one session-id forwarding test.

(ert-deftest kuro-ffi-osc-get-scrollback-count-forwards-session-id ()
  "kuro--get-scrollback-count passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 101)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback-count)
               (lambda (sid) (setq captured-sid sid) 5)))
      (kuro--get-scrollback-count)
      (should (= captured-sid 101)))))

(ert-deftest kuro-ffi-osc-set-scrollback-max-lines-forwards-session-id ()
  "kuro--set-scrollback-max-lines passes kuro--session-id as first arg."
  (let ((kuro--initialized t)
        (kuro--session-id 102)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-set-scrollback-max-lines)
               (lambda (sid _n) (setq captured-sid sid) t)))
      (kuro--set-scrollback-max-lines 500)
      (should (= captured-sid 102)))))

(ert-deftest kuro-ffi-osc-has-pending-output-forwards-session-id ()
  "kuro--has-pending-output passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 103)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-has-pending-output)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--has-pending-output)
      (should (= captured-sid 103)))))

(ert-deftest kuro-ffi-osc-poll-image-notifications-forwards-session-id ()
  "kuro--poll-image-notifications passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 104)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-poll-image-notifications)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--poll-image-notifications)
      (should (= captured-sid 104)))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-forwards-session-id ()
  "kuro--consume-scroll-events passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 105)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda (sid) (setq captured-sid sid) nil)))
      (kuro--consume-scroll-events)
      (should (= captured-sid 105)))))

(ert-deftest kuro-ffi-osc-get-scroll-offset-forwards-session-id ()
  "kuro--get-scroll-offset passes kuro--session-id to the core function."
  (let ((kuro--initialized t)
        (kuro--session-id 106)
        (captured-sid nil))
    (cl-letf (((symbol-function 'kuro-core-get-scroll-offset)
               (lambda (sid) (setq captured-sid sid) 0)))
      (kuro--get-scroll-offset)
      (should (= captured-sid 106)))))

(ert-deftest kuro-ffi-osc-get-image-forwards-image-id-large ()
  "kuro--get-image forwards large image-id values (e.g. u32 max boundary)."
  (let ((kuro--initialized t)
        (received-id nil))
    (cl-letf (((symbol-function 'kuro-core-get-image)
               (lambda (_sid id) (setq received-id id) nil)))
      (kuro--get-image 4294967295)
      (should (= received-id 4294967295)))))

;;; Group 7: value semantics, multi-entry results, and edge cases
;;
;; Tests for exact shapes of multi-entry payloads, boundary argument values,
;; and the clear-then-nil idempotency of consume-style functions.

(ert-deftest kuro-ffi-osc-get-and-clear-title-returns-string ()
  "kuro--get-and-clear-title returns the exact string provided by the core."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-and-clear-title)
               (lambda (_id) "My Terminal")))
      (should (equal "My Terminal" (kuro--get-and-clear-title))))))

(ert-deftest kuro-ffi-osc-get-and-clear-title-returns-nil-when-not-dirty ()
  "kuro--get-and-clear-title returns nil when core signals title is clean."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-and-clear-title)
               (lambda (_id) nil)))
      (should (null (kuro--get-and-clear-title))))))

(ert-deftest kuro-ffi-osc-get-cwd-returns-path-string ()
  "kuro--get-cwd returns the exact path string provided by the core."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-cwd)
               (lambda (_id) "/home/user/project")))
      (should (equal "/home/user/project" (kuro--get-cwd))))))

(ert-deftest kuro-ffi-osc-poll-clipboard-actions-multiple-entries ()
  "kuro--poll-clipboard-actions passes through a list with multiple action pairs."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-clipboard-actions)
               (lambda (_id) '((write . "text1") (query . nil) (write . "text2")))))
      (let ((result (kuro--poll-clipboard-actions)))
        (should (= (length result) 3))
        (should (eq (car (nth 0 result)) 'write))
        (should (eq (car (nth 1 result)) 'query))
        (should (null (cdr (nth 1 result))))
        (should (equal (cdr (nth 2 result)) "text2"))))))

(ert-deftest kuro-ffi-osc-poll-prompt-marks-all-mark-types ()
  "kuro--poll-prompt-marks passes through all four mark type symbols."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-prompt-marks)
               (lambda (_id)
                 '((0 . prompt-start)
                   (5 . prompt-end)
                   (6 . command-start)
                   (10 . command-end)))))
      (let ((result (kuro--poll-prompt-marks)))
        (should (= (length result) 4))
        (should (eq (cdr (nth 0 result)) 'prompt-start))
        (should (eq (cdr (nth 1 result)) 'prompt-end))
        (should (eq (cdr (nth 2 result)) 'command-start))
        (should (eq (cdr (nth 3 result)) 'command-end))))))

(ert-deftest kuro-ffi-osc-get-palette-updates-multi-entry-list ()
  "kuro--get-palette-updates passes through a list of multiple palette entries."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-palette-updates)
               (lambda (_id) '((0 0 0 0) (1 255 0 0) (15 255 255 255)))))
      (let ((result (kuro--get-palette-updates)))
        (should (= (length result) 3))
        (should (equal (nth 0 result) '(0 0 0 0)))
        (should (equal (nth 1 result) '(1 255 0 0)))
        (should (equal (nth 2 result) '(15 255 255 255)))))))

(ert-deftest kuro-ffi-osc-get-default-colors-field-layout ()
  "kuro--get-default-colors returns (FG-ENC BG-ENC CURSOR-ENC) in that order."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-default-colors)
               (lambda (_id) '(#x00FFFFFF #x00000000 #x00AAAAAA))))
      (let ((result (kuro--get-default-colors)))
        (should (= (nth 0 result) #x00FFFFFF))   ; fg
        (should (= (nth 1 result) #x00000000))   ; bg
        (should (= (nth 2 result) #x00AAAAAA)))))) ; cursor

(ert-deftest kuro-ffi-osc-get-default-colors-use-default-sentinel ()
  "kuro--get-default-colors returns #xFF000000 sentinel for use-default colors."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-default-colors)
               (lambda (_id) (list #xFF000000 #xFF000000 #xFF000000))))
      (let ((result (kuro--get-default-colors)))
        (should (= (nth 0 result) #xFF000000))
        (should (= (nth 1 result) #xFF000000))
        (should (= (nth 2 result) #xFF000000))))))

(ert-deftest kuro-ffi-osc-get-scrollback-max-lines-zero ()
  "kuro--get-scrollback with max-lines=0 forwards 0 to the core function."
  (let ((kuro--initialized t)
        (captured-max :not-set))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback)
               (lambda (_id n) (setq captured-max n) nil)))
      (kuro--get-scrollback 0)
      (should (= captured-max 0)))))

(ert-deftest kuro-ffi-osc-scroll-up-zero-lines ()
  "kuro--scroll-up with n=0 forwards 0 to the core (boundary, not filtered)."
  (let ((kuro--initialized t)
        (received-n :not-set))
    (cl-letf (((symbol-function 'kuro-core-scroll-up)
               (lambda (_id n) (setq received-n n) nil)))
      (kuro--scroll-up 0)
      (should (= received-n 0)))))

(ert-deftest kuro-ffi-osc-scroll-down-zero-lines ()
  "kuro--scroll-down with n=0 forwards 0 to the core (boundary, not filtered)."
  (let ((kuro--initialized t)
        (received-n :not-set))
    (cl-letf (((symbol-function 'kuro-core-scroll-down)
               (lambda (_id n) (setq received-n n) nil)))
      (kuro--scroll-down 0)
      (should (= received-n 0)))))

(ert-deftest kuro-ffi-osc-get-scrollback-count-large-value ()
  "kuro--get-scrollback-count passes through large line counts verbatim."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-get-scrollback-count)
               (lambda (_id) 100000)))
      (should (= 100000 (kuro--get-scrollback-count))))))

(ert-deftest kuro-ffi-osc-consume-scroll-events-both-directions ()
  "kuro--consume-scroll-events returns (UP . DOWN) when both directions occurred."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-consume-scroll-events)
               (lambda (_id) '(4 . 7))))
      (let ((result (kuro--consume-scroll-events)))
        (should (= (car result) 4))
        (should (= (cdr result) 7))))))

(provide 'kuro-ffi-osc-ext-test)

;;; kuro-ffi-osc-ext-test.el ends here
