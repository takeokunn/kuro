#!/usr/bin/env bash
# bench-validate.sh — Run parser throughput benchmarks and verify >100MB/s target
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
THRESHOLD_MB=100  # Minimum acceptable throughput in MB/s

echo "=== Kuro Benchmark Validation ==="
echo "Threshold: >${THRESHOLD_MB} MB/s"
echo ""

cd "$PROJECT_DIR"

# Run criterion benchmarks and capture output
echo "--- Running benchmarks (this may take ~30s) ---"
BENCH_OUTPUT=$(nix develop --command cargo bench --bench parser_throughput 2>&1)
echo "$BENCH_OUTPUT"

# Parse throughput from criterion output lines like:
#   parser_throughput/1MB   time:   [x.xx ms x.xx ms x.xx ms]
#   thrpt:  [xx.xx MiB/s xx.xx MiB/s xx.xx MiB/s]
# Extract MiB/s values and check against threshold

echo ""
echo "--- Parsing results ---"
PASS=true

while IFS= read -r line; do
    # Match lines with "MiB/s" or "GiB/s" throughput
    if echo "$line" | grep -qE "(MiB/s|GiB/s)"; then
        # Extract the median value (middle of three)
        if echo "$line" | grep -q "GiB/s"; then
            # GiB/s -> well above threshold
            echo "PASS: $line (GiB/s >> ${THRESHOLD_MB} MB/s)"
        else
            # Extract MiB/s median value
            MEDIAN=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+' | awk 'NR==2')
            if [ -n "$MEDIAN" ]; then
                # MiB/s ~ MB/s (close enough for our threshold check)
                if awk "BEGIN { exit !($MEDIAN >= $THRESHOLD_MB) }"; then
                    echo "PASS: ${MEDIAN} MiB/s >= ${THRESHOLD_MB} MB/s"
                else
                    echo "FAIL: ${MEDIAN} MiB/s < ${THRESHOLD_MB} MB/s"
                    PASS=false
                fi
            fi
        fi
    fi
done <<< "$BENCH_OUTPUT"

echo ""
if $PASS; then
    echo "=== BENCHMARK VALIDATION PASSED ==="
    exit 0
else
    echo "=== BENCHMARK VALIDATION FAILED ==="
    exit 1
fi
