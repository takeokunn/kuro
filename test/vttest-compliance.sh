#!/usr/bin/env bash
# vttest-compliance.sh — Run VTE compliance tests and report pass rate
# Uses the Rust vt_compliance test suite (no PTY, no tmux required)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_RATE=80  # Minimum acceptable pass rate (%)

echo "=== Kuro VTE Compliance Check ==="
echo "Target: >=${TARGET_RATE}% pass rate"
echo ""

cd "$PROJECT_DIR"

# Run only the vt_compliance integration tests
echo "--- Running vt_compliance tests ---"
OUTPUT=$(nix develop --command cargo test --test vt_compliance 2>&1)
echo "$OUTPUT"

# Extract pass/fail counts from "test result: ok. N passed; M failed"
RESULT_LINE=$(echo "$OUTPUT" | grep "^test result:")
PASSED=$(echo "$RESULT_LINE" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
FAILED=$(echo "$RESULT_LINE" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo "0")
IGNORED=$(echo "$RESULT_LINE" | grep -oE '[0-9]+ ignored' | grep -oE '[0-9]+' || echo "0")

TOTAL=$((PASSED + FAILED))
if [ "$TOTAL" -eq 0 ]; then
    echo "ERROR: No tests found"
    exit 1
fi

# Calculate pass rate
RATE=$(awk "BEGIN { printf \"%.1f\", ($PASSED / $TOTAL) * 100 }")

echo ""
echo "--- Results ---"
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Ignored: $IGNORED"
echo "  Total:   $TOTAL"
echo "  Rate:    ${RATE}%"
echo ""

if awk "BEGIN { exit !(${RATE} >= ${TARGET_RATE}) }"; then
    echo "=== COMPLIANCE CHECK PASSED (${RATE}% >= ${TARGET_RATE}%) ==="
    exit 0
else
    echo "=== COMPLIANCE CHECK FAILED (${RATE}% < ${TARGET_RATE}%) ==="
    exit 1
fi
