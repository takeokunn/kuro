#!/usr/bin/env bash
# kuro-daemon-debug.sh - Run kuro perf profiling via emacs daemon + emacsclient
#
# Usage: bash kuro-daemon-debug.sh [duration_seconds]
#   Starts kuro with bash, sends a Perl full-screen color stress loop,
#   collects kuro-debug-perf timing and Emacs CPU profiler report.
set -euo pipefail

KURO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SOCKET_NAME="kuro-perf-debug-$$"
DURATION="${1:-20}"
DYLIB="$KURO_ROOT/target/release/libkuro_core.dylib"
PERF_OUT="/tmp/kuro-perf-$$.txt"
PROFILER_OUT="/tmp/kuro-profiler-$$.txt"

# Perl stress command: each cell gets its own ANSI color (worst-case face_ranges).
# 'exec' replaces bash so PTY signals go directly to perl.
STRESS_ONELINER='exec perl -e '"'"'
use strict;
use warnings;
my ($rows, $cols) = (24, 80);
my @ch = ("A".."Z");
my $f = 0;
while (1) {
    print "\033[H\033[2J";
    for my $r (1..$rows) {
        for my $c (1..$cols) {
            my $fg = 31 + ($f + $r + $c) % 15;
            my $bg = 41 + ($f + $r*2 + $c*3) % 7;
            print "\033[${fg};${bg}m" . $ch[($f+$c+$r) % 26];
        }
        print "\033[0m\n";
    }
    $f = ($f + 1) % 256;
    select(undef, undef, undef, 0.08);
}
'"'"
# Append newline to submit the command in bash
STRESS_CMD="${STRESS_ONELINER}"$'\n'

echo "=== kuro daemon debug session ==="
echo "  KURO_ROOT : $KURO_ROOT"
echo "  dylib     : $DYLIB"
echo "  duration  : ${DURATION}s"
echo ""

[[ -f "$DYLIB" ]] || { echo "ERROR: run 'make build' first"; exit 1; }

# Clean up leftover socket
emacsclient --socket-name="$SOCKET_NAME" -e '(kill-emacs)' 2>/dev/null || true
sleep 0.3

echo "[1/6] Starting emacs -Q daemon ($SOCKET_NAME)..."
emacs -Q --daemon="$SOCKET_NAME" 2>/dev/null
sleep 1.0

EC="emacsclient --socket-name=$SOCKET_NAME"

echo "[2/6] Loading kuro, enabling kuro-debug-perf, starting CPU profiler..."
$EC -e "
(progn
  (add-to-list 'load-path \"$KURO_ROOT/emacs-lisp/core\")
  (setq kuro-module-binary-path \"$DYLIB\")
  (require 'kuro)
  (setq kuro-debug-perf t)
  (profiler-start 'cpu)
  \"ready\")"

echo "[3/6] Opening GUI frame and starting kuro with bash..."
# -c opens a real NS frame; emacsclient blocks until the frame is closed
$EC -c -e "(kuro-create \"bash\" \"*kuro-stress*\")" &
FRAME_PID=$!

echo "[4/6] Waiting 3s for bash to start, then sending stress command..."
sleep 3.0

# Send the Perl stress one-liner to the running bash
$EC -e "
(when (buffer-live-p (get-buffer \"*kuro-stress*\"))
  (with-current-buffer \"*kuro-stress*\"
    (kuro--send-key $(printf '%s' "$STRESS_CMD" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')))
  \"sent\")" 2>&1

echo "[5/6] Collecting data for ${DURATION}s..."
sleep "$DURATION"

echo "[6/6] Stopping profiler and collecting results..."
$EC -e "
(progn
  (profiler-stop)
  (when (get-buffer \"*kuro-perf*\")
    (with-current-buffer \"*kuro-perf*\"
      (write-region (point-min) (point-max) \"$PERF_OUT\")))
  (let ((rb (profiler-report-cpu)))
    (when (buffer-live-p rb)
      (with-current-buffer rb
        (write-region (point-min) (point-max) \"$PROFILER_OUT\"))))
  \"done\")" 2>&1 || true

# Cleanup
wait "$FRAME_PID" 2>/dev/null &
$EC -e '(kill-emacs)' 2>/dev/null || true
wait "$FRAME_PID" 2>/dev/null || true

echo ""
echo "=== *kuro-perf* timing log ==="
if [[ -f "$PERF_OUT" && -s "$PERF_OUT" ]]; then
    cat "$PERF_OUT"
else
    echo "(no perf output — kuro render loop may not have fired)"
fi

echo ""
echo "=== CPU profiler top entries ==="
if [[ -f "$PROFILER_OUT" && -s "$PROFILER_OUT" ]]; then
    head -100 "$PROFILER_OUT"
else
    echo "(no profiler output)"
fi
