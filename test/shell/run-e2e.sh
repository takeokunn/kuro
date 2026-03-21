#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "=== Kuro E2E Test Runner ==="
echo "Project: $PROJECT_DIR"

# Build Rust core first
echo ""
echo "--- Building Rust core ---"
cd "$PROJECT_DIR"
cargo build --release 2>&1

echo ""
echo "--- Running E2E tests ---"
emacs -Q --batch \
  -L "$PROJECT_DIR/emacs-lisp" \
  -L "$PROJECT_DIR/test/unit" \
  -L "$PROJECT_DIR/test/integration" \
  --eval "(require 'kuro)" \
  --eval "(require 'kuro-e2e-test)" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-e2e\")" \
  2>&1

echo ""
echo "--- Running config unit tests ---"
emacs -Q --batch \
  -L "$PROJECT_DIR/emacs-lisp" \
  -L "$PROJECT_DIR/test/unit" \
  -L "$PROJECT_DIR/test/integration" \
  --eval "(require 'kuro-config)" \
  --eval "(require 'kuro-config-test)" \
  --eval "(ert-run-tests-batch-and-exit \"test-kuro\")" \
  2>&1

echo ""
echo "--- Running unit tests (kuro-unit-* in kuro-e2e-test.el) ---"
emacs -Q --batch \
  -L "$PROJECT_DIR/emacs-lisp" \
  -L "$PROJECT_DIR/test/unit" \
  -L "$PROJECT_DIR/test/integration" \
  --eval "(require 'kuro)" \
  --eval "(require 'kuro-e2e-test)" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-unit\")" \
  2>&1
