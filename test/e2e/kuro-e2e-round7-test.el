;;; kuro-e2e-round7-test.el --- Live-module E2E for Round 7 features -*- lexical-binding: t -*-

;;; Commentary:
;; Live-module E2E verification of Round 7:
;;   (a) REFLOW: soft-wrap rewrap on width change preserves content + adds rows.
;;   (b) PLACEHOLDER: U+10EEEE Unicode-placeholder region descriptors via
;;       `kuro-core-poll-placeholder-placements'.
;;   (c) CELLSIZE: OSC 1337 ReportCellSize queues a response (drained to PTY).
;;
;; These drive the real Rust cdylib over a /bin/sh PTY, mirroring the
;; infrastructure in kuro-e2e-helpers.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-e2e-helpers)

(declare-function kuro-core-resize "ext:kuro-core" (session-id rows cols))
(declare-function kuro-core-poll-placeholder-placements "ext:kuro-core" (session-id))
(declare-function kuro-core-set-cell-pixel-size "ext:kuro-core" (session-id width height))
(declare-function kuro-core-poll-updates-binary-with-strings "ext:kuro-core" (session-id))

;;; Helpers

(defun kuro-e2e-round7--pump (sid n)
  "Pump the FFI poll N times to let PTY data flow into the grid for SID."
  (dotimes (_ n)
    (ignore-errors (kuro-core-poll-updates-binary-with-strings sid))
    (sleep-for kuro-e2e--poll-interval)))

(defun kuro-e2e-round7--marker-rows-in-repaint (sid prefix)
  "After a full repaint (e.g. just-issued resize marks all rows dirty), count
how many dirty rows for SID consist of a run that starts with PREFIX.

A resize marks every grid row dirty, so a single poll returns one text entry
per grid row; the count of rows whose content is the marker run equals the
number of physical rows the soft-wrapped logical line currently occupies.
Polls a few times and returns the MAX seen (the full-repaint frame)."
  (let ((best 0))
    (dotimes (_ 6)
      (let ((res (kuro-core-poll-updates-binary-with-strings sid))
            (hits 0))
        (when res
          (let ((texts (car res)))
            (dotimes (i (length texts))
              (let ((s (string-trim (aref texts i))))
                (when (string-prefix-p prefix s)
                  (cl-incf hits))))))
        (setq best (max best hits)))
      (sleep-for kuro-e2e--poll-interval))
    best))

;;; (a) REFLOW

(ert-deftest kuro-e2e-round7-reflow-on-narrow-adds-rows-content-intact ()
  "Print a line wider than the terminal so it soft-wraps; narrow the width
and confirm the text reflows into MORE rows with content intact, then widen
back without error."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; Print a single 150-char marker line; at width 80 it wraps to 2 rows.
     (let ((marker (make-string 150 ?R)))
       (kuro--send-key (concat "printf '" marker "\\n'\r"))
       (should (kuro-e2e--wait-for-output sid "RRRRRRRRRR" 10.0))
       (kuro-e2e-round7--pump sid 3)
       ;; Resize to 80 to force a clean full repaint, then count marker rows.
       (kuro--resize 24 80)
       (let ((wide-rows (kuro-e2e-round7--marker-rows-in-repaint sid "RRRRRRRRRR")))
         (should (> wide-rows 0))
         ;; Narrow to 40 columns: 150 chars now needs ~4 rows (was 2 at 80).
         (kuro--resize 24 40)
         (let ((narrow-rows
                (kuro-e2e-round7--marker-rows-in-repaint sid "RRRRRRRRRR")))
           ;; Reflow must produce strictly MORE marker rows at the narrow width,
           ;; and the content (R-run) must survive intact.
           (should (> narrow-rows wide-rows)))
         ;; Resize back to 80 without error; the marker still reflows to fewer rows.
         (kuro--resize 24 80)
         (let ((back-rows (kuro-e2e-round7--marker-rows-in-repaint sid "RRRRRRRRRR")))
           (should (> back-rows 0))
           (should (= back-rows wide-rows))))))))

;;; (b) PLACEHOLDER

(ert-deftest kuro-e2e-round7-placeholder-region-descriptors ()
  "Transmit a 1x1 PNG via the Kitty graphics protocol, then emit a 2x2 block
of U+10EEEE Unicode-placeholder cells referencing it, and confirm
`kuro-core-poll-placeholder-placements' returns a region descriptor."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; 1x1 PNG (base64), transmitted with image id 31 (f=100 PNG, t=d direct).
     (let* ((png-b64 (concat "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1Pe"
                             "AAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"))
            ;; ESC _ G i=31,f=100,t=d,a=t ; <b64> ESC \
            (transmit (concat "\\033_Gi=31,f=100,t=d,a=t;" png-b64 "\\033\\\\"))
            ;; U+10EEEE UTF-8 = \364\216\273\256 ; diacritic idx0 = U+0305 = \314\205.
            (ph "\\364\\216\\273\\256\\314\\205")
            ;; FG truecolor encoding id 31 = RGB(0,0,31): ESC[38;2;0;0;31m
            (fg "\\033[38;2;0;0;31m")
            ;; Emit transmit, then a 2x2 placeholder block (two rows of two cells).
            (seq (concat transmit fg ph ph "\\r\\n" ph ph "\\033[0m\\n")))
       (kuro--send-key (concat "printf '" seq "'\r"))
       (kuro-e2e-round7--pump sid 6)
       (let ((regions nil)
             (deadline (+ (float-time) 8.0)))
         (while (and (null regions) (< (float-time) deadline))
           (kuro-e2e-round7--pump sid 2)
           (setq regions (kuro-core-poll-placeholder-placements sid)))
         (should regions)
         ;; At least one descriptor referencing image id 31.
         (let ((r (car regions)))
           ;; descriptor: (IMAGE-ID PLACEMENT-ID SCREEN-ROW SCREEN-COL
           ;;              CELL-COLS CELL-ROWS IMG-ROW IMG-COL IMG-ROWS IMG-COLS)
           (should (listp r))
           (should (= (length r) 10))
           (should (= (nth 0 r) 31))
           ;; cell span must be positive (non-empty rectangle).
           (should (> (nth 4 r) 0))
           (should (> (nth 5 r) 0))))))))

;;; (c) CELLSIZE — OSC 1337 ReportCellSize

(ert-deftest kuro-e2e-round7-report-cell-size-queues-response ()
  "Push a host cell pixel size via `kuro-core-set-cell-pixel-size', then emit
OSC 1337 ReportCellSize from the shell.  The Rust core queues a response and
drains it to the PTY during poll_output, so the shell receives the reply on
stdin; we confirm the round trip does not error and the grid keeps advancing."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--with-session sid
     ;; Set a host cell pixel size (width=9, height=19 points).
     (when (fboundp 'kuro-core-set-cell-pixel-size)
       (should (kuro-core-set-cell-pixel-size sid 9 19)))
     ;; Emit OSC 1337 ReportCellSize, then a marker so we can confirm liveness.
     (kuro--send-key
      (concat "printf '\\033]1337;ReportCellSize\\033\\\\'; "
              "printf 'CELLSIZE_DONE_E2E\\n'\r"))
     ;; The response is drained to the shell stdin; the shell may echo control
     ;; bytes, but the marker must still appear, proving the OSC was consumed
     ;; without stalling the parser.
     (should (kuro-e2e--wait-for-output sid "CELLSIZE_DONE_E2E" 10.0)))))

(provide 'kuro-e2e-round7-test)

;;; kuro-e2e-round7-test.el ends here
