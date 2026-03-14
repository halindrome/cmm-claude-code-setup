#!/bin/bash
# Main benchmark orchestrator — runs 6 variants × 5 repos × 5 tasks × n runs, writes raw CSV

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../config.sh
source "$SCRIPT_DIR/../config.sh"
# shellcheck source=./variant-setup.sh
source "$SCRIPT_DIR/variant-setup.sh"

DRY_RUN=false
FILTER_REPO=""
FILTER_TASK=""
FILTER_VARIANT=""
RUN_DELAY=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --repo)    FILTER_REPO="$2"; shift 2 ;;
    --task)    FILTER_TASK="$2"; shift 2 ;;
    --variant) FILTER_VARIANT="$2"; shift 2 ;;
    --runs)    BENCH_RUNS="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Resolve absolute paths relative to this script
RESULTS_DIR="$SCRIPT_DIR/../results"
PROMPTS_DIR="$SCRIPT_DIR/../prompts"
OVERRIDES="$PROMPTS_DIR/repo-overrides.json"

mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CSV_FILE="$RESULTS_DIR/raw-${TIMESTAMP}.csv"

echo "variant,repo,task,run,input_tokens,output_tokens,cache_creation,cache_read,total_tokens" > "$CSV_FILE"
echo "[run-benchmarks] Output: $CSV_FILE"

FAILED=0

for repo in "${BENCH_REPOS[@]}"; do
  [[ -n "$FILTER_REPO" && "$repo" != "$FILTER_REPO" ]] && continue

  REPO_PATH="$SCRIPT_DIR/../repos/${repo}"
  export REPO_PATH

  for variant in "${BENCH_VARIANTS[@]}"; do
    [[ -n "$FILTER_VARIANT" && "$variant" != "$FILTER_VARIANT" ]] && continue

    # Skip ctx and cmm+ctx* variants if context-mode binary is not installed
    if [[ "$variant" == "ctx" || "$variant" == cmm+ctx* ]]; then
      if ! command -v context-mode &>/dev/null; then
        echo "[skip] $variant variant skipped — context-mode not found" >&2
        continue
      fi
    fi

    for task_num in 01 02 03 04 05; do
      [[ -n "$FILTER_TASK" && "$task_num" != "$FILTER_TASK" ]] && continue

      PROMPT_FILE="$PROMPTS_DIR/${task_num}-"*.txt
      # expand glob
      PROMPT_FILE_EXPANDED=$(ls "$PROMPTS_DIR/${task_num}"-*.txt 2>/dev/null | head -1)
      if [[ -z "$PROMPT_FILE_EXPANDED" ]]; then
        echo "[warn] No prompt file for task $task_num — skipping" >&2
        continue
      fi

      SEARCH_TERM=$(jq -r --arg repo "$repo" --arg task "$task_num" '.[$repo][$task] // "TODO"' "$OVERRIDES")
      PROMPT_TEMPLATE=$(cat "$PROMPT_FILE_EXPANDED")
      PROMPT="${PROMPT_TEMPLATE//\{SEARCH_TERM\}/$SEARCH_TERM}"

      for run in $(seq 1 "$BENCH_RUNS"); do
        echo "[run] variant=$variant repo=$repo task=$task_num run=$run"

        if $DRY_RUN; then
          echo "  DRY RUN: variant=$variant repo=$repo task=$task_num run=$run"
          echo "$variant,$repo,$task_num,$run,0,0,0,0,0" >> "$CSV_FILE"
          continue
        fi

        # Run claude --print from the benchmark repo directory (not the project root)
        # The .mcp.json swap targets the repo dir so claude picks up the right MCP config
        MCP_JSON="$REPO_PATH/.mcp.json" setup_variant "$variant"

        START_TS=$(date +%s)

        if ! (cd "$REPO_PATH" && claude --print "$PROMPT" > /dev/null 2>&1); then
          echo "[error] claude --print failed for variant=$variant repo=$repo task=$task_num run=$run" >&2
          MCP_JSON="$REPO_PATH/.mcp.json" teardown_variant "$variant"
          FAILED=1
          continue
        fi

        SESSION=$(bash "$SCRIPT_DIR/find-session.sh" --after "$START_TS" 2>/dev/null)
        if [[ -z "$SESSION" ]]; then
          echo "[error] Could not find session JSONL after $START_TS" >&2
          MCP_JSON="$REPO_PATH/.mcp.json" teardown_variant "$variant"
          FAILED=1
          continue
        fi

        TOKENS=$(bash "$SCRIPT_DIR/parse-tokens.sh" "$SESSION" 2>/dev/null)
        if [[ -z "$TOKENS" ]]; then
          echo "[error] parse-tokens.sh returned empty for $SESSION" >&2
          MCP_JSON="$REPO_PATH/.mcp.json" teardown_variant "$variant"
          FAILED=1
          continue
        fi

        echo "$variant,$repo,$task_num,$run,$TOKENS" >> "$CSV_FILE"

        MCP_JSON="$REPO_PATH/.mcp.json" teardown_variant "$variant"

        sleep "$RUN_DELAY"
      done
    done
  done
done

echo "[run-benchmarks] Running aggregation..."
AGG_FILE="${CSV_FILE/raw-/aggregated-}"
bash "$SCRIPT_DIR/aggregate-stats.sh" "$CSV_FILE" > "$AGG_FILE"
echo "[run-benchmarks] Aggregated CSV: $AGG_FILE"
echo "[run-benchmarks] Raw CSV: $CSV_FILE"

# Export for callers
echo "$CSV_FILE"

if [[ $FAILED -ne 0 ]]; then
  echo "[run-benchmarks] Completed with errors — check log above" >&2
  exit 1
fi

exit 0
