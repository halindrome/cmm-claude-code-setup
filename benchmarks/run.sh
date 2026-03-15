#!/bin/bash
# End-to-end benchmark runner: prerequisite checks → setup repos → run benchmarks → report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prereq() {
  local cmd="$1" required="$2" label="${3:-$1}"
  if ! command -v "$cmd" &>/dev/null; then
    if [[ "$required" == "required" ]]; then
      echo "[error] Required tool not found: $label" >&2
      echo "        Install $label and re-run." >&2
      exit 1
    else
      echo "[warn]  Optional tool not found: $label — some features may be limited" >&2
    fi
  fi
}

check_prereq jq           required "jq"
check_prereq claude       required "claude CLI"
check_prereq git          required "git"
check_prereq codebase-memory-mcp warn "codebase-memory-mcp"

# ---------------------------------------------------------------------------
# Parse flags (pass-through to run-benchmarks.sh)
# ---------------------------------------------------------------------------
PASS_THROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  PASS_THROUGH_ARGS+=("$1")
  shift
done

# ---------------------------------------------------------------------------
# Step 1: Setup repos
# ---------------------------------------------------------------------------
echo "[run.sh] Step 1/3 — Setting up benchmark repos..."
bash "$SCRIPT_DIR/scripts/setup-repos.sh"

# ---------------------------------------------------------------------------
# Step 2: Run benchmarks (outputs raw CSV path on last stdout line)
# ---------------------------------------------------------------------------
echo "[run.sh] Step 2/3 — Running benchmarks..."
BENCH_RC=0
RAW_CSV=$(bash "$SCRIPT_DIR/scripts/run-benchmarks.sh" "${PASS_THROUGH_ARGS[@]}" | tail -1) || BENCH_RC=$?

if [[ -z "$RAW_CSV" || ! -f "$RAW_CSV" ]]; then
  echo "[error] run-benchmarks.sh did not produce a valid CSV path: '${RAW_CSV}'" >&2
  exit 1
fi

if [[ $BENCH_RC -ne 0 ]]; then
  echo "[warn] Some benchmark runs failed (exit $BENCH_RC) — generating report from partial data" >&2
fi

echo "[run.sh] Raw CSV: $RAW_CSV"

# ---------------------------------------------------------------------------
# Step 3: Generate report (aggregation already done by run-benchmarks.sh)
# ---------------------------------------------------------------------------
AGG_CSV="${RAW_CSV/raw-/aggregated-}"
echo "[run.sh] Step 3/3 — Generating report..."
REPORT=$(bash "$SCRIPT_DIR/scripts/generate-report.sh" "$AGG_CSV" | tail -1)

echo ""
echo "================================================================"
echo "Report saved to: $REPORT"
echo "================================================================"

exit "$BENCH_RC"
