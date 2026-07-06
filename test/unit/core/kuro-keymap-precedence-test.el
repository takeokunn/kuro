;;; kuro-keymap-precedence-test.el --- ERT tests for Kuro's emulation-mode-map-alists precedence  -*- lexical-binding: t; -*-

;;; Commentary:

;; Regression coverage for GitHub issue #1 (Kuro's PTY-forwarding keymap
;; losing Emacs key-lookup precedence against evil-mode/god-mode/etc.) and
;; the related shared-keymap-object bug fixed alongside it.  These tests
;; exercise the *real* `kuro-mode' derived-mode body (via plain
;; `(kuro-mode)' in a temp buffer, never the simplified isolated-testing
;; stub used by some `kuro-input-mode-test-*.el' harnesses), because the
;; guarantees checked here depend on `kuro--install-input-mode-keymap'
;; actually running and registering `kuro--emulation-mode-map-alist'.
;;
;; Groups:
;;   Group 1 — shadow-keymap simulation: a stub minor mode registered in
;;     `minor-mode-map-alist' (which sits below `emulation-mode-map-alists'
;;     but above the ordinary buffer-local map in Emacs's keymap search
;;     order) must still lose to Kuro's `kuro--emulation-mode-map-alist'
;;     entry.  Verified with `key-binding', which walks real cross-alist
;;     precedence; `lookup-key' alone only probes a single keymap object
;;     and does not exercise this ordering.
;;   Group 2 — copy-mode exclusion: entering copy mode suspends Kuro's
;;     precedence (the stub wins again); exiting restores it.
;;   Group 3 — cross-buffer non-leakage: switching one kuro-mode buffer's
;;     input mode must not affect a second, simultaneously open kuro-mode
;;     buffer's effective local keymap or `kuro--emulation-mode-map-alist',
;;     and must never mutate the shared `kuro-mode-map' object itself.
;;   Group 4 — `emulation-mode-map-alists' head-position reassertion: a
;;     package registering its own entry ahead of Kuro's (simulating one
;;     that loads or activates after Kuro) must be displaced back behind
;;     Kuro's entry the next time `kuro--install-input-mode-keymap' runs.
;;   Group 5 — line-mode shadow-outranked scenario, `kuro--set-keymap-exceptions'
;;     per-buffer re-derivation, and real cross-input-mode reachability of
;;     `kuro-mode-map's own commands.

;;; Code:

(require 'kuro-test-support)

;;; ── Helpers ──────────────────────────────────────────────────────────────────

(defun kuro-keymap-precedence-test--stub-command ()
  "Stub minor-mode command standing in for a higher-priority package.
Must never be reached while Kuro's PTY-forwarding keymap has precedence."
  (interactive)
  (error "kuro-keymap-precedence-test--stub-command: shadow command was reached"))

(defvar kuro-keymap-precedence-test--stub-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-k") #'kuro-keymap-precedence-test--stub-command)
    map)
  "Keymap for the stub minor mode simulating a higher-priority package.")

(defvar-local kuro-keymap-precedence-test--stub-mode nil
  "Buffer-local flag activating the stub minor mode's `minor-mode-map-alist' entry.")

(defmacro kuro-keymap-precedence-test--with-shadow (&rest body)
  "Run BODY with a stub minor mode shadowing C-k active in the current buffer.
The stub is registered as a plain `minor-mode-map-alist' entry — which, per
Emacs's keymap search order, sits below `emulation-mode-map-alists' but
above the ordinary buffer-local map — simulating \"a plain minor-mode
package with lower priority than Kuro's own `emulation-mode-map-alists'
entry, but higher priority than Kuro's local map used to have\".  The
dynamic `let' binding keeps the mutation scoped to BODY so it cannot leak
into other tests sharing this Emacs batch session."
  (declare (indent 0))
  `(let ((minor-mode-map-alist
          (cons (cons 'kuro-keymap-precedence-test--stub-mode
                      kuro-keymap-precedence-test--stub-map)
                minor-mode-map-alist)))
     (setq-local kuro-keymap-precedence-test--stub-mode t)
     ,@body))

(defmacro kuro-keymap-precedence-test--with-two-buffers (buf-a buf-b &rest body)
  "Bind BUF-A and BUF-B to two live, real `kuro-mode' buffers for BODY.
Both buffers are unconditionally killed afterwards."
  (declare (indent 2))
  `(let ((,buf-a (generate-new-buffer "*kuro-keymap-precedence-test-a*"))
         (,buf-b (generate-new-buffer "*kuro-keymap-precedence-test-b*")))
     (unwind-protect
         (progn
           (with-current-buffer ,buf-a (kuro-mode))
           (with-current-buffer ,buf-b (kuro-mode))
           ,@body)
       (when (buffer-live-p ,buf-a) (kill-buffer ,buf-a))
       (when (buffer-live-p ,buf-b) (kill-buffer ,buf-b)))))

(defun kuro-keymap-precedence-test--stub-command-line ()
  "Stub minor-mode command shadowing a key untouched by line-mode overrides.
Standing in for a higher-priority package, same as
`kuro-keymap-precedence-test--stub-command' but bound to C-v instead of
C-k, since C-k is itself rebound by `kuro--line-mode-bindings'
\(`kuro--line-kill-line') and so cannot be used to test that line mode's
*parent* keymap (`kuro--keymap') still outranks a shadowing package for
keys line mode does not override.  Must never be reached while Kuro's
PTY-forwarding keymap has precedence."
  (interactive)
  (error "kuro-keymap-precedence-test--stub-command-line: shadow command was reached"))

(defvar kuro-keymap-precedence-test--stub-map-line
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-v") #'kuro-keymap-precedence-test--stub-command-line)
    map)
  "Keymap for the stub minor mode simulating a higher-priority package,
shadowing C-v (absent from `kuro--line-mode-bindings') for line-mode tests.")

(defvar-local kuro-keymap-precedence-test--stub-mode-line nil
  "Buffer-local flag activating the C-v-shadowing stub minor mode's
`minor-mode-map-alist' entry.")

(defmacro kuro-keymap-precedence-test--with-shadow-line (&rest body)
  "Run BODY with a stub minor mode shadowing C-v active in the current buffer.
Mirrors `kuro-keymap-precedence-test--with-shadow' but targets C-v, a key
`kuro--line-mode-bindings' does not rebind, so it stays reachable via
line mode's parent keymap (`kuro--keymap') rather than a line-mode-local
override."
  (declare (indent 0))
  `(let ((minor-mode-map-alist
          (cons (cons 'kuro-keymap-precedence-test--stub-mode-line
                      kuro-keymap-precedence-test--stub-map-line)
                minor-mode-map-alist)))
     (setq-local kuro-keymap-precedence-test--stub-mode-line t)
     ,@body))

(defun kuro-keymap-precedence-test--flatten (keymap)
  "Collect every (EVENT . BINDING) pair reachable in KEYMAP via `map-keymap'.
Unlike `lookup-key' (which stops at the first match and can return a
prefix-depth integer for nested/composed maps), `map-keymap' walks every
constituent of a composed keymap, including shadowed entries, so two
keymap snapshots can be compared structurally without depending on
lookup precedence."
  (let (entries)
    (map-keymap (lambda (event binding) (push (cons event binding) entries)) keymap)
    (nreverse entries)))

;;; ── Group 1 — shadow-keymap simulation (issue #1 regression guard) ─────────

(ert-deftest kuro-keymap-precedence-test-shadow-outranked-in-semi-char-mode ()
  "In semi-char mode, `key-binding' resolves C-k to Kuro's PTY-forwarding
command via `kuro--emulation-mode-map-alist', not the shadowing stub
minor-mode command registered in `minor-mode-map-alist', and not a
fallback to any ordinary Emacs binding."
  (with-temp-buffer
    (kuro-mode)
    (kuro-keymap-precedence-test--with-shadow
      (let ((forwarding-cmd (lookup-key kuro--keymap (kbd "C-k"))))
        (should (functionp forwarding-cmd))
        (should (eq (key-binding (kbd "C-k")) forwarding-cmd))
        (should-not (eq (key-binding (kbd "C-k"))
                        #'kuro-keymap-precedence-test--stub-command))))))

(ert-deftest kuro-keymap-precedence-test-shadow-outranked-in-char-mode ()
  "Same guarantee as the semi-char case, but in char mode (all keys
forwarded, no `kuro-keymap-exceptions' holes)."
  (with-temp-buffer
    (kuro-mode)
    (kuro-char-mode)
    (kuro-keymap-precedence-test--with-shadow
      (let ((forwarding-cmd (lookup-key kuro--char-keymap (kbd "C-k"))))
        (should (functionp forwarding-cmd))
        (should (eq (key-binding (kbd "C-k")) forwarding-cmd))
        (should-not (eq (key-binding (kbd "C-k"))
                        #'kuro-keymap-precedence-test--stub-command))))))

(ert-deftest kuro-keymap-precedence-test-emulation-alist-entry-matches-local-map ()
  "`kuro--emulation-mode-map-alist' holds the exact same composed-keymap
object installed via `use-local-map', confirming `key-binding' consults
the live effective map rather than a stale snapshot."
  (with-temp-buffer
    (kuro-mode)
    (should (eq (caar kuro--emulation-mode-map-alist) t))
    (should (eq (cdar kuro--emulation-mode-map-alist) (current-local-map)))))

;;; ── Group 2 — copy-mode exclusion ───────────────────────────────────────────

(ert-deftest kuro-keymap-precedence-test-copy-mode-suspends-forwarding-precedence ()
  "Entering copy mode nils out `kuro--emulation-mode-map-alist', letting the
shadowing stub minor-mode win C-k again."
  (with-temp-buffer
    (kuro-mode)
    (kuro-keymap-precedence-test--with-shadow
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
        (kuro--enter-copy-mode)
        (should (null kuro--emulation-mode-map-alist))
        (should (eq (key-binding (kbd "C-k"))
                    #'kuro-keymap-precedence-test--stub-command))
        (kuro--exit-copy-mode)))))

(ert-deftest kuro-keymap-precedence-test-exit-copy-mode-restores-forwarding-precedence ()
  "Exiting copy mode reinstalls `kuro--emulation-mode-map-alist', restoring
Kuro's PTY-forwarding precedence over the shadowing stub minor-mode."
  (with-temp-buffer
    (kuro-mode)
    (kuro-keymap-precedence-test--with-shadow
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
        (kuro--enter-copy-mode)
        (kuro--exit-copy-mode)
        (let ((forwarding-cmd (lookup-key kuro--keymap (kbd "C-k"))))
          (should (eq (key-binding (kbd "C-k")) forwarding-cmd))
          (should-not (eq (key-binding (kbd "C-k"))
                          #'kuro-keymap-precedence-test--stub-command)))))))

;;; ── Group 3 — cross-buffer non-leakage ──────────────────────────────────────

(ert-deftest kuro-keymap-precedence-test-mode-switch-does-not-leak-across-buffers ()
  "Switching buffer A's input mode leaves buffer B's effective local keymap
and `kuro--emulation-mode-map-alist' completely unchanged, both by object
identity and by `map-keymap' structural comparison."
  (kuro-keymap-precedence-test--with-two-buffers buf-a buf-b
    (with-current-buffer buf-a (kuro-char-mode))
    (with-current-buffer buf-b (kuro-line-mode))
    (let ((buf-b-map-before (with-current-buffer buf-b (current-local-map)))
          (buf-b-alist-before (with-current-buffer buf-b kuro--emulation-mode-map-alist))
          (buf-b-flat-before (with-current-buffer buf-b
                               (kuro-keymap-precedence-test--flatten (current-local-map)))))
      (with-current-buffer buf-a (kuro-semi-char-mode))
      (with-current-buffer buf-b
        (should (eq (current-local-map) buf-b-map-before))
        (should (eq kuro--emulation-mode-map-alist buf-b-alist-before))
        (should (equal (kuro-keymap-precedence-test--flatten (current-local-map))
                       buf-b-flat-before))
        (should (eq kuro--input-mode 'line))))))

(ert-deftest kuro-keymap-precedence-test-mode-map-parent-never-mutated ()
  "`kuro-mode-map's `keymap-parent' is left completely unchanged by
input-mode switches in two simultaneously open buffers: nothing in the
production keymap-installation path calls `set-keymap-parent' on the
shared object anymore.  Compares against a snapshot taken immediately
before switching (rather than assuming any particular baseline value),
since sibling test files intentionally mutate this shared keymap's parent
for their own, unrelated legacy-compat test harness."
  (kuro-keymap-precedence-test--with-two-buffers buf-a buf-b
    (let ((baseline (keymap-parent kuro-mode-map)))
      (with-current-buffer buf-a (kuro-char-mode))
      (should (eq (keymap-parent kuro-mode-map) baseline))
      (with-current-buffer buf-b (kuro-line-mode))
      (should (eq (keymap-parent kuro-mode-map) baseline))
      (with-current-buffer buf-a (kuro-semi-char-mode))
      (should (eq (keymap-parent kuro-mode-map) baseline)))))

;;; ── Group 4 — emulation-mode-map-alists head-position reassertion ──────────
;;; (issue #1 fix regression guard: another package registering into
;;; `emulation-mode-map-alists' after Kuro must not keep precedence.)

(ert-deftest kuro-keymap-precedence-test-install-reasserts-head-position ()
  "If some other entry is manually prepended ahead of Kuro's in
`emulation-mode-map-alists' (simulating a package such as evil-mode
registering itself after Kuro already loaded), calling
`kuro--install-input-mode-keymap' again — as every mode-switch command
does — restores `kuro--emulation-mode-map-alist' to the head of the
list."
  (with-temp-buffer
    (kuro-mode)
    (should (eq (car emulation-mode-map-alists) 'kuro--emulation-mode-map-alist))
    (let ((emulation-mode-map-alists
           (cons 'kuro-keymap-precedence-test--other-package-alist
                 emulation-mode-map-alists)))
      (should-not (eq (car emulation-mode-map-alists) 'kuro--emulation-mode-map-alist))
      (kuro--install-input-mode-keymap)
      (should (eq (car emulation-mode-map-alists) 'kuro--emulation-mode-map-alist))
      (should (memq 'kuro-keymap-precedence-test--other-package-alist
                    emulation-mode-map-alists)))))

;;; ── Group 5 — line-mode shadow-outranked, exceptions re-derivation, and ────
;;; real cross-input-mode command reachability ───────────────────────────────

(ert-deftest kuro-keymap-precedence-test-shadow-outranked-in-line-mode ()
  "In line mode, `key-binding' resolves C-v — a key `kuro--line-mode-bindings'
does not rebind — to Kuro's PTY-forwarding command from `kuro--keymap' (line
mode's parent keymap), not the shadowing stub minor-mode command, and not a
fallback to any ordinary Emacs binding."
  (with-temp-buffer
    (kuro-mode)
    (kuro-line-mode)
    (kuro-keymap-precedence-test--with-shadow-line
      (let ((forwarding-cmd (lookup-key kuro--keymap (kbd "C-v"))))
        (should (functionp forwarding-cmd))
        (should (eq (key-binding (kbd "C-v")) forwarding-cmd))
        (should-not (eq (key-binding (kbd "C-v"))
                        #'kuro-keymap-precedence-test--stub-command-line))))))

(ert-deftest kuro-keymap-precedence-test-set-keymap-exceptions-rederives-per-buffer ()
  "`kuro--set-keymap-exceptions' rebuilds every live `kuro-mode' buffer's
effective keymap from that buffer's OWN `kuro--input-mode', not from one
shared value: a buffer left in char mode and a buffer left in line mode
must still end up with keymaps appropriate to their own mode — and
structurally different from each other — after the shared exceptions
list changes out from under them."
  (let ((original-exceptions kuro-keymap-exceptions))
    (unwind-protect
        (kuro-keymap-precedence-test--with-two-buffers buf-a buf-b
          (with-current-buffer buf-a (kuro-char-mode))
          (with-current-buffer buf-b (kuro-line-mode))
          (kuro--set-keymap-exceptions 'kuro-keymap-exceptions '("C-c"))
          (with-current-buffer buf-a
            (should (eq kuro--input-mode 'char))
            (should (eq (lookup-key (current-local-map) [remap self-insert-command])
                        #'kuro--self-insert)))
          (with-current-buffer buf-b
            (should (eq kuro--input-mode 'line))
            (should (eq (lookup-key (current-local-map) [remap self-insert-command])
                        #'kuro--line-self-insert)))
          (should-not
           (equal (with-current-buffer buf-a
                    (kuro-keymap-precedence-test--flatten (current-local-map)))
                  (with-current-buffer buf-b
                    (kuro-keymap-precedence-test--flatten (current-local-map))))))
      (kuro--set-keymap-exceptions 'kuro-keymap-exceptions original-exceptions))))

(ert-deftest kuro-keymap-precedence-test-own-commands-reachable-across-input-modes ()
  "`kuro-mode-map's own C-c-prefixed commands (e.g. `kuro-copy-mode',
bound to `C-c C-t') stay reachable via `key-binding' in a real, unmocked
`kuro-mode' buffer no matter which input mode is currently active."
  (with-temp-buffer
    (kuro-mode)
    (kuro-char-mode)
    (should (eq (key-binding (kbd "C-c C-t")) #'kuro-copy-mode))
    (kuro-semi-char-mode)
    (should (eq (key-binding (kbd "C-c C-t")) #'kuro-copy-mode))
    (kuro-line-mode)
    (should (eq (key-binding (kbd "C-c C-t")) #'kuro-copy-mode))))

(provide 'kuro-keymap-precedence-test)
;;; kuro-keymap-precedence-test.el ends here
