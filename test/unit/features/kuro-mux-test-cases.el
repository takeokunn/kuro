;;; kuro-mux-test-cases.el --- Case data for kuro-mux tests  -*- lexical-binding: t; -*-

;;; Code:

(defconst kuro-mux-test--name-lighter-table
  '((kuro-mux-test-lighter-returns-name-in-braces "*mux-lt1*" "dev" " {dev}")
    (kuro-mux-test-lighter-empty-when-no-name "*mux-lt2*" nil ""))
  "Cases for `kuro-mux--name-lighter'.")

(defconst kuro-mux-test--session-spec-table
  '((kuro-mux-test-session-spec-includes-name
     "*mux-sp1*" kuro-mux--name :name "test-session")
    (kuro-mux-test-session-spec-includes-command
     "*mux-sp2*" kuro-mux--command :command "fish")
    (kuro-mux-test-session-spec-includes-directory
     "*mux-sp3*" kuro-mux--directory :directory "/tmp"))
  "Cases for `kuro-mux--session-spec'.")

(defconst kuro-mux-test--parse-layout-plists-table
  '((kuro-mux-test-parse-layout-plists-single
     ((:name "dev" :command "bash" :directory "/tmp"))
     1
     (:name "dev" :command "bash" :directory "/tmp"))
    (kuro-mux-test-parse-layout-plists-multiple
     ((:name "a" :command "sh" :directory "/a")
      (:name "b" :command "zsh" :directory "/b"))
     2
     (:name "a"))
    (kuro-mux-test-parse-layout-plists-empty
     nil
     0
     nil)
    (kuro-mux-test-parse-layout-plists-drops-invalid
     ((:name "ok" :command "bash") "not-a-list" (:name "broken"))
     1
     (:name "ok")))
  "Cases for `kuro-mux--parse-layout-plists'.")

(defconst kuro-mux-test--prefix-bindings-invariant-table
  '((kuro-mux-test-prefix-bindings-is-non-empty
     "`kuro-mux--prefix-bindings' is a non-empty alist."
     (should (consp kuro-mux--prefix-bindings)))
    (kuro-mux-test-prefix-bindings-all-keys-are-strings
     "Every key in `kuro-mux--prefix-bindings' is a non-empty string."
     (dolist (entry kuro-mux--prefix-bindings)
       (should (stringp (car entry)))
       (should (> (length (car entry)) 0))))
    (kuro-mux-test-prefix-bindings-all-values-are-symbols
     "Every value in `kuro-mux--prefix-bindings' is a symbol."
     (dolist (entry kuro-mux--prefix-bindings)
       (should (symbolp (cdr entry)))))
    (kuro-mux-test-prefix-bindings-all-installed-in-map
     "Every entry in `kuro-mux--prefix-bindings' is correctly installed in the map."
     (dolist (entry kuro-mux--prefix-bindings)
       (let ((key (car entry))
             (fn (cdr entry)))
         (should (eq (lookup-key kuro-mux-prefix-map (kbd key)) fn)))))
    (kuro-mux-test-prefix-bindings-count
     "`kuro-mux--prefix-bindings' has at least 30 entries."
     (should (>= (length kuro-mux--prefix-bindings) 30))))
  "Cases for `kuro-mux--prefix-bindings'.")

(defconst kuro-mux-test--prefix-resize-bindings-invariant-table
  '((kuro-mux-test-prefix-resize-bindings-has-four-entries
     "`kuro-mux--prefix-resize-bindings' has exactly 4 arrow entries."
     (should (= (length kuro-mux--prefix-resize-bindings) 4)))
    (kuro-mux-test-prefix-resize-bindings-all-entries-have-three-elements
     "Every resize binding entry has exactly 3 elements (key dir delta)."
     (dolist (entry kuro-mux--prefix-resize-bindings)
       (should (= (length entry) 3))))
    (kuro-mux-test-prefix-resize-bindings-all-keys-are-strings
     "Every resize binding key is a non-empty string."
     (dolist (entry kuro-mux--prefix-resize-bindings)
       (should (stringp (car entry)))
       (should (> (length (car entry)) 0))))
    (kuro-mux-test-prefix-resize-bindings-covers-all-directions
     "`kuro-mux--prefix-resize-bindings' covers all four arrow directions."
     (let ((dirs (mapcar #'cadr kuro-mux--prefix-resize-bindings)))
       (should (memq 'up dirs))
       (should (memq 'down dirs))
       (should (memq 'left dirs))
       (should (memq 'right dirs))))
    (kuro-mux-test-prefix-resize-bindings-all-deltas-positive
     "Every resize binding delta is a positive integer."
     (dolist (entry kuro-mux--prefix-resize-bindings)
       (let ((delta (caddr entry)))
         (should (integerp delta))
         (should (> delta 0))))))
  "Cases for `kuro-mux--prefix-resize-bindings'.")

(provide 'kuro-mux-test-cases)
;;; kuro-mux-test-cases.el ends here
