;;; kuro-input-paste-test-2.el --- kuro-input-paste-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-paste-test-support)

;;; Group 4: kuro--send-paste-or-raw dispatch

(kuro-paste-test--deftest-send-paste-or-raws)

;;; Group 5: kuro--yank dispatch

(kuro-paste-test--deftest-yank-renders)
(kuro-paste-test--deftest-yank-args)
(kuro-paste-test--deftest-yank-errors)

;;; Group 6: kuro--yank-pop edge cases

(kuro-paste-test--deftest-yank-pop-renders)
(kuro-paste-test--deftest-yank-pop-last-commands)

;;; Group 7: kuro--yank and kuro--yank-pop additional dispatch cases

(kuro-paste-test--deftest-yank-extras)
(kuro-paste-test--deftest-extra-errors)
(kuro-paste-test--deftest-initial-values)

(provide 'kuro-input-paste-test-2)
;;; kuro-input-paste-test-2.el ends here
