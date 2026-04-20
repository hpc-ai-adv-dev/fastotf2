#!/usr/bin/env bash
# full_parity_test.sh — End-to-end parity verification across all strategies and formats.
#
# Proves by transitivity that all strategies produce identical output in both CSV and Parquet:
#   1. CSV↔Parquet parity within each strategy  (CallgraphParityTest + MetricsParityTest)
#   2. Parquet↔Parquet parity between strategy 1 and every subsequent strategy
#      (StrategyParquetParityTest)
#
# Usage:
#   cd apps/FastOTF2Converter
#   . ~/dev/spack/share/spack/setup-env.sh && spack env activate arrow-19
#   bash test/full_parity_test.sh [trace_path]
#
# Default trace: ../../scorep-traces/simple-mi300-example-run/traces.otf2

set -euo pipefail

# ---------------------------------------------------------------------------
# configuration
# ---------------------------------------------------------------------------

TRACE="${1:-../../scorep-traces/simple-mi300-example-run/traces.otf2}"

CSV_DIR="/tmp/csv_out"
PQ_DIR="/tmp/pq_out"
OLD_PQ_DIR="/tmp/old_pq_out"
NEW_PQ_DIR="/tmp/new_pq_out"

CONVERTER="./target/release/FastOTF2Converter"
CALLGRAPH_TEST="./target/test/CallgraphParityTest"
METRICS_TEST="./target/test/MetricsParityTest"
STRATEGY_TEST="./target/test/StrategyParquetParityTest"

STRATEGIES=(
  serial
  loc_block
  locgroup_block
  locgroup_dist_block
)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

log_header() {
  echo ""
  echo "================================================================"
  echo "  $1"
  echo "================================================================"
}

log_step() {
  echo "--- $1"
}

run_converter() {
  local strategy="$1"
  local format="$2"
  local outdir="$3"

  log_step "Running: --strategy=$strategy --format=$format --outputDir=$outdir"
  rm -rf "$outdir"
  "$CONVERTER" "$TRACE" \
    --strategy="$strategy" --format="$format" --outputDir="$outdir" --log=ERROR
}

# Run a test binary, show only result lines, return the binary's exit code.
run_test() {
  local binary="$1"
  shift
  local output rc=0
  output=$("$binary" "$@" 2>&1) || rc=$?
  echo "$output" | grep -E "^Ran |FAILED|ERROR" || true
  return $rc
}

run_format_parity_tests() {
  local rc=0
  log_step "Running CSV↔Parquet parity tests (CallgraphParityTest + MetricsParityTest)"
  run_test "$CALLGRAPH_TEST" --csvDir="$CSV_DIR" --pqDir="$PQ_DIR" || rc=1
  run_test "$METRICS_TEST" --csvDir="$CSV_DIR" --pqDir="$PQ_DIR" || rc=1
  return $rc
}

run_all_parity_tests() {
  local rc=0
  log_step "Running all parity tests (format + strategy)"
  run_test "$CALLGRAPH_TEST" --csvDir="$CSV_DIR" --pqDir="$PQ_DIR" || rc=1
  run_test "$METRICS_TEST" --csvDir="$CSV_DIR" --pqDir="$PQ_DIR" || rc=1
  run_test "$STRATEGY_TEST" --oldDir="$OLD_PQ_DIR" --newDir="$NEW_PQ_DIR" || rc=1
  return $rc
}

snapshot_baseline() {
  log_step "Snapshotting $PQ_DIR → $OLD_PQ_DIR (baseline)"
  rm -rf "$OLD_PQ_DIR"
  cp -r "$PQ_DIR" "$OLD_PQ_DIR"
}

snapshot_comparison() {
  log_step "Snapshotting $PQ_DIR → $NEW_PQ_DIR (comparison)"
  rm -rf "$NEW_PQ_DIR"
  cp -r "$PQ_DIR" "$NEW_PQ_DIR"
}

# ---------------------------------------------------------------------------
# preflight: build everything once
# ---------------------------------------------------------------------------

if [[ ! -f "$TRACE" ]]; then
  echo "ERROR: trace not found: $TRACE"
  exit 1
fi

log_header "Building converter + tests"
mason build --release 2>&1 | tail -1
mason test --no-run --keep-binary 2>&1 | grep -E "Compiled|ERROR" || true

# Verify binaries exist
for bin in "$CONVERTER" "$CALLGRAPH_TEST" "$METRICS_TEST" "$STRATEGY_TEST"; do
  if [[ ! -x "$bin" ]]; then
    echo "ERROR: binary not found after build: $bin"
    exit 1
  fi
done

log_header "Full Parity Test — ${#STRATEGIES[@]} strategies × 2 formats"
echo "Trace: $TRACE"
echo "Strategies: ${STRATEGIES[*]}"

passed=0
failed=0

# ---------------------------------------------------------------------------
# strategy 1 (baseline): generate CSV + Parquet, test format parity, snapshot
# ---------------------------------------------------------------------------

baseline="${STRATEGIES[0]}"
log_header "Strategy 1/${#STRATEGIES[@]}: $baseline (baseline)"

run_converter "$baseline" CSV "$CSV_DIR"
run_converter "$baseline" PARQUET "$PQ_DIR"

if run_format_parity_tests; then
  passed=$((passed + 1))
else
  failed=$((failed + 1))
fi

snapshot_baseline

# ---------------------------------------------------------------------------
# strategies 2..N: generate, test format parity + cross-strategy parity
# ---------------------------------------------------------------------------

for i in $(seq 1 $(( ${#STRATEGIES[@]} - 1 ))); do
  strategy="${STRATEGIES[$i]}"
  log_header "Strategy $(($i + 1))/${#STRATEGIES[@]}: $strategy"

  run_converter "$strategy" CSV "$CSV_DIR"
  run_converter "$strategy" PARQUET "$PQ_DIR"

  snapshot_comparison

  if run_all_parity_tests; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------

log_header "Results"
echo "Strategies tested: ${#STRATEGIES[@]}"
echo "  Passed: $passed"
echo "  Failed: $failed"

if [[ "$failed" -gt 0 ]]; then
  echo "FAIL"
  exit 1
else
  echo "ALL PASS — all strategies × formats produce identical output"
  exit 0
fi
