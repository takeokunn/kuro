;;; kuro-ffi-osc-test-2.el --- kuro-ffi-osc tests: session-id forwarding + value semantics  -*- lexical-binding: t; -*-

;;; Commentary:
;; Continuation of kuro-ffi-osc-test.el (split to keep files under 600 lines).
;; Groups 6-7: session-id forwarding coverage + value semantics / edge cases.

;;; Code:

(require 'ert)
(require 'seq)

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (unit-dir (expand-file-name ".." this-dir)))
  (add-to-list 'load-path unit-dir))
(require 'kuro-test-stubs)

(defvar kuro--initialized nil)

(require 'kuro-ffi-osc)


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
  "kuro--poll-clipboard-actions passes through strict clipboard actions."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro-core-poll-clipboard-actions)
               (lambda (_id) '((write "text1" "clipboard")
                               (query nil "clipboard")
                               (write "text2" "clipboard")))))
      (let ((result (kuro--poll-clipboard-actions)))
        (should (= (length result) 3))
        (should (eq (car (nth 0 result)) 'write))
        (should (eq (car (nth 1 result)) 'query))
        (should (equal (cadr (nth 1 result)) nil))
        (should (equal (caddr (nth 1 result)) "clipboard"))
        (should (equal (cadr (nth 2 result)) "text2"))
        (should (equal (caddr (nth 2 result)) "clipboard"))))))

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


(provide 'kuro-ffi-osc-test-2)

;;; kuro-ffi-osc-test-2.el ends here
