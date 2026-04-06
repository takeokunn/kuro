#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

echo "=== Kuro E2E Test Runner ==="
echo "Project: $PROJECT_DIR"

# Build Rust core only when a pre-built module is not already provided.
# In CI, set KURO_MODULE_PATH before invoking this script (e.g. via
# `nix build .#kuro-core`) to skip the cargo build step entirely.
if [ -z "${KURO_MODULE_PATH:-}" ]; then
  echo ""
  echo "--- Building Rust core ---"
  cd "$PROJECT_DIR"
  cargo build --release 2>&1
  export KURO_MODULE_PATH="$PROJECT_DIR/target/release"
else
  echo ""
  echo "--- Using pre-built module from $KURO_MODULE_PATH ---"
fi

echo ""
echo "--- Running E2E tests ---"
emacs -Q --batch \
  -L "$PROJECT_DIR/emacs-lisp/core" \
  -L "$PROJECT_DIR/test/e2e" \
  --eval "(require 'kuro)" \
  --eval "(require 'kuro-e2e-helpers)" \
  --eval "(mapc #'load (directory-files-recursively \
    \"$PROJECT_DIR/test/e2e\" \"-test\\\\.el\$\"))" \
  --eval "(ert-run-tests-batch-and-exit \"kuro-e2e\")" \
  2>&1
