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

(provide 'kuro-mux-test-cases)
;;; kuro-mux-test-cases.el ends here
