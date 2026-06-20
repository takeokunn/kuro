;;; kuro-e2e-tui-test.el --- TUI and heavy-app E2E tests -*- lexical-binding: t -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Phase 4 ApexTerm E2E verification: TUI application support.
;;
;; Test categories:
;;   1. ANSI SGR output — bold, 24-bit truecolor, extended underline styles
;;   2. Alternate screen buffer — smcup/rmcup round-trip
;;   3. Large output streaming — no UI-thread blocking
;;   4. tmux terminal-in-terminal (skip-unless tmux is installed)
;;   5. Bracketed paste — mode toggle does not corrupt output

;;; Code:

(require 'ert)
(require 'kuro-e2e-helpers)

;;; Group 1 — ANSI SGR output

(ert-deftest kuro-e2e-ansi-bold-text ()
  "Bold SGR (ESC[1m) does not corrupt text — plain content still matches."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (should (kuro-e2e--send-command-and-wait kuro--session-id
                                            "printf '\\033[1mKURO_BOLD_TEST\\033[0m\\n'\r"
                                            "KURO_BOLD_TEST"))))

(ert-deftest kuro-e2e-ansi-truecolor-output ()
  "24-bit truecolor SGR (ESC[38;2;R;G;Bm) does not corrupt text content."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (should (kuro-e2e--send-command-and-wait kuro--session-id
                                            "printf '\\033[38;2;255;0;128mKURO_COLOR_TEST\\033[0m\\n'\r"
                                            "KURO_COLOR_TEST"))))

(ert-deftest kuro-e2e-ansi-underline-extended ()
  "Extended underline (CSI 4:3 m — curly underline) does not corrupt text."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; CSI 4:3 m = curly/wavy underline (Kitty graphics extension)
   (should (kuro-e2e--send-command-and-wait kuro--session-id
                                            "printf '\\033[4:3mKURO_CURL_TEST\\033[0m\\n'\r"
                                            "KURO_CURL_TEST"))))

(ert-deftest kuro-e2e-ansi-combined-attrs ()
  "Multiple SGR attributes combined (bold + italic + truecolor) do not corrupt text."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; CSI 1;3;38;2;0;200;100 m = bold + italic + RGB foreground
   (should (kuro-e2e--send-command-and-wait kuro--session-id
                                            "printf '\\033[1;3;38;2;0;200;100mKURO_COMBO_TEST\\033[0m\\n'\r"
                                            "KURO_COMBO_TEST"))))

;;; Group 2 — Alternate screen buffer (smcup / rmcup)

(ert-deftest kuro-e2e-alternate-screen-enter-exit ()
  "tput smcup enters alt screen; text written there is detected before rmcup."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; TERM=xterm-256color (set by the Rust PTY spawner) makes tput work.
     ;; shell-side sleep 0.5 keeps the terminal on the alt screen long enough
     ;; for the 100ms polling loop to detect the content before rmcup fires.
     (kuro--send-key
      "tput smcup && printf 'KURO_ALT_SCREEN\\n' && sleep 0.5 && tput rmcup\r")
     (should (kuro-e2e--wait-for-output sid "KURO_ALT_SCREEN"
                                        kuro-e2e--slow-timeout)))))

(ert-deftest kuro-e2e-alternate-screen-returns-primary ()
  "After rmcup, primary screen output (echo after rmcup) is visible."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     (kuro--send-key
      "tput smcup && sleep 0.1 && tput rmcup && echo KURO_AFTER_RMCUP\r")
     (should (kuro-e2e--wait-for-output sid "KURO_AFTER_RMCUP"
                                        kuro-e2e--slow-timeout)))))

(ert-deftest kuro-e2e-alternate-screen-raw-escape ()
  "Raw DEC private mode 1049 (CSI ? 1049 h/l) switches alt screen correctly."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; CSI ? 1049 h = save cursor + enter alt screen (xterm)
     ;; CSI ? 1049 l = exit alt screen + restore cursor
     (kuro--send-key
      "printf '\\033[?1049h'; printf 'KURO_RAW_ALT\\n'; sleep 0.5; printf '\\033[?1049l'\r")
     (should (kuro-e2e--wait-for-output sid "KURO_RAW_ALT"
                                        kuro-e2e--slow-timeout)))))

;;; Group 3 — Large output streaming (no UI-thread blocking)

(ert-deftest kuro-e2e-large-output-no-blocking ()
  "500-line seq command streams without timing out."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (should (kuro-e2e--send-command-and-wait kuro--session-id
                                            "seq 1 500\r"
                                            "500"))))

(ert-deftest kuro-e2e-large-ansi-output-streaming ()
  "500-line truecolor output stream does not block the polling loop."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Each line: CSI 38;2;color;100;200 m + number + reset.  500 lines ×
   ;; ~30 bytes = ~15KB of ANSI-encoded output — a real-world log burst.
   (kuro--send-key
    (concat "seq 1 500 | while read i; do"
            " printf '\\033[38;2;%d;100;200m%d\\033[0m\\n' "
            "\"$((i % 256))\" \"$i\";"
            " done\r"))
   (should (kuro-e2e--wait-for-output kuro--session-id "500"
                                      kuro-e2e--slow-timeout))))

(ert-deftest kuro-e2e-mixed-output-and-echo ()
  "Sequential commands after large output still produce visible output."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     (should (kuro-e2e--send-command-and-wait sid "seq 1 200\r" "200"))
     ;; After the burst, a simple echo must still work.
     (should (kuro-e2e--send-command-and-wait sid "echo KURO_AFTER_BURST\r"
                                              "KURO_AFTER_BURST")))))

;;; Group 4 — tmux terminal-in-terminal

(defconst kuro-e2e--tmux-available
  (and (executable-find "tmux") t)
  "Non-nil when tmux is installed and executable on this system.")

(ert-deftest kuro-e2e-tmux-session-start ()
  "tmux starts inside kuro and its status bar renders without garbling."
  :expected-result kuro-e2e--expected-result
  (skip-unless kuro-e2e--tmux-available)
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; Use a per-process socket name to avoid colliding with the user's tmux.
     ;; $$ expands to the shell PID in bash — unique per test run.
     (kuro--send-key
      "tmux -L kuro-e2e-$$ new-session -s kuro-test \"sleep 2\"\r")
     ;; tmux status bar shows the session name.
     (should (kuro-e2e--wait-for-output sid "kuro-test"
                                        kuro-e2e--slow-timeout))
     ;; The short-lived command exits on its own, avoiding dangling tmux servers.
     )))

(ert-deftest kuro-e2e-tmux-inner-echo ()
  "Commands sent inside tmux produce visible output (terminal-in-terminal)."
  :expected-result kuro-e2e--expected-result
  (skip-unless kuro-e2e--tmux-available)
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     (kuro--send-key
      "tmux -L kuro-e2e2-$$ new-session -s kuro-inner \"sh -c 'sleep 0.5; echo KURO_INSIDE_TMUX; sleep 2'\"\r")
     (should (kuro-e2e--wait-for-output sid "kuro-inner"
                                        kuro-e2e--slow-timeout))
     (should (kuro-e2e--wait-for-output sid "KURO_INSIDE_TMUX"
                                        kuro-e2e--slow-timeout)))))

(ert-deftest kuro-e2e-tmux-seq-output ()
  "seq inside tmux streams 10 lines without garbling."
  :expected-result kuro-e2e--expected-result
  (skip-unless kuro-e2e--tmux-available)
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     (kuro--send-key
      "tmux -L kuro-e2e3-$$ new-session -s kuro-seq \"sh -c 'sleep 0.5; seq 1 10; sleep 2'\"\r")
     (should (kuro-e2e--wait-for-output sid "kuro-seq"
                                        kuro-e2e--slow-timeout))
     (should (kuro-e2e--wait-for-output sid "10"
                                        kuro-e2e--slow-timeout)))))

;;; Group 5 — Bracketed paste

(ert-deftest kuro-e2e-bracketed-paste-mode-toggle ()
  "Enabling then disabling bracketed paste mode does not corrupt subsequent output."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; CSI ? 2004 h = enable bracketed paste; CSI ? 2004 l = disable
     (kuro--send-key "\033[?2004h")
     (kuro--send-key "\033[?2004l")
     ;; Give the mode toggle a chance to settle before the next command.
     (sleep-for kuro-e2e--poll-interval)
     ;; Output after toggling must still be clean.
     (should (kuro-e2e--send-command-and-wait sid "echo KURO_AFTER_PASTE_TOGGLE\r"
                                              "KURO_AFTER_PASTE_TOGGLE")))))

(ert-deftest kuro-e2e-bracketed-paste-content ()
  "A bracketed paste sequence does not corrupt subsequent shell input."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; The shell is invoked with --norc --noprofile; bash itself may or may
     ;; not enable bracketed paste in this environment.  Raw paste markers are
     ;; therefore environment-dependent shell input, so clear that line and
     ;; verify the terminal remains usable for the next command.
     (kuro--send-key
      (concat "\033[200~"       ; start-of-paste bracket
              "echo KURO_IGNORED_PASTE"
              "\033[201~"))     ; end-of-paste bracket
     (kuro--send-key "\025")     ; C-u clears readline's current input line.
     (should (kuro-e2e--send-command-and-wait sid "echo KURO_PASTE\r"
                                              "KURO_PASTE"
                                              kuro-e2e--slow-timeout)))))

;;; Group 6 — emacs -nw recursive (Phase 4)

(defconst kuro-e2e--emacs-available
  (and (executable-find "emacs") t)
  "Non-nil when `emacs' is on PATH (needed for recursive emacs -nw test).")

(defconst kuro-e2e--emacs-nw-visible-pattern
  "\\(GNU Emacs\\|\\*scratch\\*\\)"
  "Text pattern that proves recursive `emacs -nw' is on screen.")

(defun kuro-e2e--emacs-nw-command (marker)
  "Return a shell command that launches `emacs -nw' and prints MARKER after exit."
  (concat "emacs --no-init-file --no-site-file --no-splash -nw "
          "--eval \"(run-at-time 1 nil #'save-buffers-kill-terminal)\"; "
          "echo " marker "\r"))

(ert-deftest kuro-e2e-emacs-nw-starts ()
  "emacs -nw starts inside kuro and the GNU Emacs title or scratch is visible."
  :expected-result kuro-e2e--expected-result
  (skip-unless kuro-e2e--emacs-available)
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; --no-init-file --no-site-file gives a deterministic minimal emacs.
     ;; --batch is NOT used: we need the interactive TUI.
     (kuro--send-key (kuro-e2e--emacs-nw-command "KURO_AFTER_EMACS_STARTS"))
     (should (kuro-e2e--wait-for-output sid kuro-e2e--emacs-nw-visible-pattern
                                        kuro-e2e--slow-timeout))
     (should (kuro-e2e--wait-for-output sid "KURO_AFTER_EMACS_STARTS"
                                        kuro-e2e--slow-timeout)))))

(ert-deftest kuro-e2e-emacs-nw-scratch-buffer ()
  "emacs -nw shows the *scratch* buffer contents inside kuro."
  :expected-result kuro-e2e--expected-result
  (skip-unless kuro-e2e--emacs-available)
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     (kuro--send-key (kuro-e2e--emacs-nw-command "KURO_AFTER_SCRATCH"))
     (should (kuro-e2e--wait-for-output sid kuro-e2e--emacs-nw-visible-pattern
                                        kuro-e2e--slow-timeout))
     (should (kuro-e2e--wait-for-output sid "KURO_AFTER_SCRATCH"
                                        kuro-e2e--slow-timeout)))))

(ert-deftest kuro-e2e-emacs-nw-returns-to-shell ()
  "After exiting emacs -nw, the outer shell prompt is restored."
  :expected-result kuro-e2e--expected-result
  (skip-unless kuro-e2e--emacs-available)
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     (kuro--send-key
      (concat "kuro_after=KURO_AFTER_; "
              (kuro-e2e--emacs-nw-command "${kuro_after}NW")))
     (should (kuro-e2e--wait-for-output sid kuro-e2e--emacs-nw-visible-pattern
                                        kuro-e2e--slow-timeout))
     ;; Confirm the following shell command runs after emacs exits.
     (should (kuro-e2e--wait-for-output sid "KURO_AFTER_NW"
                                        kuro-e2e--slow-timeout)))))

(provide 'kuro-e2e-tui-test)
;;; kuro-e2e-tui-test.el ends here
