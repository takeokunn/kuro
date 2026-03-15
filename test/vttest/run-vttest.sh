#!/bin/bash
# VTtest harness runner - tests VTE compliance without PTY

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT"

echo "=== Kuro VTtest Harness ==="
echo ""

# Build first
echo "Building Rust core..."
cargo build --release 2>&1 | tail -5

# Run unit tests in batch mode (no PTY)
echo ""
echo "Running vttest-style unit tests..."

emacs --batch -L emacs-lisp -L test \
    --eval "(require 'kuro)" \
    --eval "(require 'vttest-harness)" \
    --eval "(ert-run-tests-batch-and-exit \"vttest\")"

echo ""
echo "=== VTtest harness complete ==="
