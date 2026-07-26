#!/usr/bin/env bash
# bench-validate.sh - Run parser throughput benchmarks and enforce workload-specific targets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
PARSER_THRESHOLD_MIB=38
PLAIN_TEXT_THRESHOLD_MIB=95

echo "=== Kuro Benchmark Validation ==="
echo "Parser threshold: >= ${PARSER_THRESHOLD_MIB} MiB/s"
echo "Plain-text threshold: >= ${PLAIN_TEXT_THRESHOLD_MIB} MiB/s"
echo ""

cd "$PROJECT_DIR"

echo "--- Running benchmarks (this may take ~30s) ---"
BENCH_OUTPUT=$(nix develop --command cargo bench --bench parser_throughput 2>&1)
printf '%s\n' "$BENCH_OUTPUT"

echo ""
echo "--- Parsing results ---"
PASS=true
RESULT_COUNT=0

while IFS=$'\t' read -r GROUP MEDIAN UNIT; do
    [ -n "$MEDIAN" ] || continue
    RESULT_COUNT=$((RESULT_COUNT + 1))

    case "$GROUP" in
        parser_throughput) THRESHOLD_MIB=$PARSER_THRESHOLD_MIB ;;
        plain_text_throughput) THRESHOLD_MIB=$PLAIN_TEXT_THRESHOLD_MIB ;;
        *)
            echo "FAIL: unsupported benchmark group: $GROUP"
            PASS=false
            continue
            ;;
    esac

    MEDIAN_MIB=$(perl -e '
        my ($value, $unit) = @ARGV;
        my %factor = ("KiB/s" => 1 / 1024, "MiB/s" => 1, "GiB/s" => 1024);
        die "unsupported throughput unit: $unit\n" unless exists $factor{$unit};
        printf "%.6f", $value * $factor{$unit};
    ' "$MEDIAN" "$UNIT")

    if perl -e 'exit !($ARGV[0] >= $ARGV[1])' "$MEDIAN_MIB" "$THRESHOLD_MIB"; then
        echo "PASS: ${MEDIAN} ${UNIT} (${MEDIAN_MIB} MiB/s) >= ${THRESHOLD_MIB} MiB/s"
    else
        echo "FAIL: ${MEDIAN} ${UNIT} (${MEDIAN_MIB} MiB/s) < ${THRESHOLD_MIB} MiB/s"
        PASS=false
    fi
done < <(printf '%s\n' "$BENCH_OUTPUT" | perl -ne '
    my $number = qr/[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/;
    my $unit = qr/(?:KiB|MiB|GiB)\/s/;
    if (/^(parser_throughput|plain_text_throughput)\//) {
        $group = $1;
    }
    if (/thrpt:\s*\[\s*$number\s+$unit\s+($number)\s+($unit)\s+$number\s+$unit\s*\]/) {
        die "throughput result without benchmark group\n" unless defined $group;
        print "$group\t$1\t$2\n";
    }
')

echo ""
if [ "$RESULT_COUNT" -eq 0 ]; then
    echo "FAIL: Criterion output contained no parseable throughput results"
    echo "=== BENCHMARK VALIDATION FAILED ==="
    exit 1
fi

if $PASS; then
    echo "=== BENCHMARK VALIDATION PASSED (${RESULT_COUNT} results) ==="
    exit 0
fi

echo "=== BENCHMARK VALIDATION FAILED ==="
exit 1
