#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

echo "=== Kuro E2E Test Runner ==="
echo "Project: $PROJECT_DIR"

# Build Rust core first
echo ""
echo "--- Building Rust core ---"
cd "$PROJECT_DIR"
cargo build --release 2>&1

# Collect all test/unit subdirectories for load-path
UNIT_PATHS=""
for dir in "$PROJECT_DIR"/test/unit/*/; do
  [ -d "$dir" ] && UNIT_PATHS="$UNIT_PATHS -L $dir"
done

echo ""
echo "--- Running E2E tests ---"
export KURO_MODULE_PATH="$PROJECT_DIR/target/release"
emacs -Q --batch \
  -L "$PROJECT_DIR/emacs-lisp/core" \
  $UNIT_PATHS \
  -L "$PROJECT_DIR/test/integration" \
  --eval "(require 'kuro)" \
  --eval "(require 'kuro-e2e-test)" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-e2e\")" \
  2>&1
