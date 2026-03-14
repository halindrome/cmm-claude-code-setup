#!/bin/bash
# Generate a Markdown benchmark report from an aggregated CSV, filling REPORT-TEMPLATE.md

set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <aggregated.csv>" >&2
  exit 1
fi

AGG_CSV="$1"
if [[ ! -f "$AGG_CSV" ]]; then
  echo "Error: File not found: $AGG_CSV" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../results/REPORT-TEMPLATE.md"
RESULTS_DIR="$SCRIPT_DIR/../results"
TODAY=$(date +%Y-%m-%d)
OUTPUT="$RESULTS_DIR/REPORT-${TODAY}.md"

CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
CMM_VERSION=$(codebase-memory-mcp --version 2>/dev/null || echo "unknown")
CTX_VERSION=$(context-mode --version 2>/dev/null || echo "unknown")

# Extract n_runs from the CSV (first data row, column 4)
N_RUNS=$(awk -F',' 'NR==2{print $4}' "$AGG_CSV")
[[ -z "$N_RUNS" ]] && N_RUNS="?"

# ---------------------------------------------------------------------------
# Compute per-variant summary (mean ± stddev of total_mean across all rows)
# Columns: 1=variant 2=repo 3=task 4=n 5=input_mean 6=input_stddev
#          7=output_mean 8=output_stddev 9=cache_creation_mean 10=cache_creation_stddev
#          11=cache_read_mean 12=cache_read_stddev 13=total_mean 14=total_stddev
# We compute the grand mean and pooled stddev of total_mean across rows per variant.
# ---------------------------------------------------------------------------

SUMMARY_TABLE=$(awk -F',' '
NR == 1 { next }
{
  variant = $1
  total_mean = $13+0
  total_stddev = $14+0
  sum[variant]    += total_mean
  sum_sq[variant] += total_mean * total_mean
  count[variant]++
  # track baseline for reduction calc
}
function fmt_pct(base_mean, v_mean,    pct) {
  if (base_mean == 0) return "N/A"
  pct = (v_mean - base_mean) / base_mean * 100
  if (pct >= 0) return sprintf("+%.1f%%", pct)
  return sprintf("%.1f%%", pct)
}
END {
  # compute per-variant grand mean
  for (v in sum) {
    n = count[v]
    grand_mean[v] = sum[v] / n
    variance = (sum_sq[v] / n) - (grand_mean[v] * grand_mean[v])
    if (variance < 0) variance = 0
    grand_stddev[v] = sqrt(variance)
  }
  base_mean = grand_mean["baseline"]
  # print in fixed order
  variants[1] = "baseline"; variants[2] = "cmm-cold"; variants[3] = "cmm-cache"
  variants[4] = "ctx"; variants[5] = "cmm+ctx-cold"; variants[6] = "cmm+ctx-cache"
  for (i = 1; i <= 6; i++) {
    v = variants[i]
    if (!(v in count)) continue
    vs_baseline = (v == "baseline") ? "—" : fmt_pct(base_mean, grand_mean[v])
    printf "| %s | %.0f | %.0f | %s |\n", v, grand_mean[v], grand_stddev[v], vs_baseline
  }
}
' "$AGG_CSV")

# ---------------------------------------------------------------------------
# Per-repo table: mean total by repo and variant
# ---------------------------------------------------------------------------
PER_REPO_TABLE=$(awk -F',' '
NR == 1 { next }
{
  variant = $1; repo = $2
  total_mean = $13+0
  sum[repo SUBSEP variant] += total_mean
  count[repo SUBSEP variant]++
  repos[repo] = 1
}
END {
  # enumerate repos deterministically
  repo_list[1]="expressjs/express"; repo_list[2]="go-chi/chi"
  repo_list[3]="httpie/cli"; repo_list[4]="redis/redis"
  repo_list[5]="meilisearch/meilisearch"
  variants[1]="baseline"; variants[2]="cmm-cold"; variants[3]="cmm-cache"
  variants[4]="ctx"; variants[5]="cmm+ctx-cold"; variants[6]="cmm+ctx-cache"
  for (ri = 1; ri <= 5; ri++) {
    r = repo_list[ri]
    if (!(r in repos)) continue
    printf "| %s", r
    for (vi = 1; vi <= 6; vi++) {
      v = variants[vi]
      if (count[r SUBSEP v] > 0)
        printf " | %.0f", sum[r SUBSEP v] / count[r SUBSEP v]
      else
        printf " | N/A"
    }
    printf " |\n"
  }
}
' "$AGG_CSV")

# ---------------------------------------------------------------------------
# Per-task table: mean total by task and variant
# ---------------------------------------------------------------------------
PER_TASK_TABLE=$(awk -F',' '
NR == 1 { next }
{
  variant = $1; task = $3
  total_mean = $13+0
  sum[task SUBSEP variant] += total_mean
  count[task SUBSEP variant]++
  tasks[task] = 1
}
END {
  task_labels[1]="01"; task_labels[2]="02"; task_labels[3]="03"
  task_labels[4]="04"; task_labels[5]="05"
  task_names[1]="01-find-callers"; task_names[2]="02-call-graph"
  task_names[3]="03-list-exports"; task_names[4]="04-find-imports"
  task_names[5]="05-dead-code"
  variants[1]="baseline"; variants[2]="cmm-cold"; variants[3]="cmm-cache"
  variants[4]="ctx"; variants[5]="cmm+ctx-cold"; variants[6]="cmm+ctx-cache"
  for (ti = 1; ti <= 5; ti++) {
    t = task_labels[ti]
    if (!(t in tasks)) continue
    printf "| %s", task_names[ti]
    for (vi = 1; vi <= 6; vi++) {
      v = variants[vi]
      if (count[t SUBSEP v] > 0)
        printf " | %.0f", sum[t SUBSEP v] / count[t SUBSEP v]
      else
        printf " | N/A"
    }
    printf " |\n"
  }
}
' "$AGG_CSV")

# ---------------------------------------------------------------------------
# Build report from template using awk multi-line replacement
# ---------------------------------------------------------------------------
# Write computed tables to temp files so newlines survive shell handoff
SUMMARY_FILE=$(mktemp)
REPO_FILE=$(mktemp)
TASK_FILE=$(mktemp)
printf '%s\n' "$SUMMARY_TABLE" > "$SUMMARY_FILE"
printf '%s\n' "$PER_REPO_TABLE" > "$REPO_FILE"
printf '%s\n' "$PER_TASK_TABLE" > "$TASK_FILE"

awk \
  -v date="$TODAY" \
  -v claude_ver="$CLAUDE_VERSION" \
  -v cmm_ver="$CMM_VERSION" \
  -v n_runs="$N_RUNS" \
'
{
  gsub(/YYYY-MM-DD/, date)
  gsub(/claude-XXXXXX/, claude_ver)
  gsub(/X\.X\.X/, cmm_ver)
  gsub(/\*\*n \(runs per variant\/repo\/task\):\*\* N/, "**n (runs per variant/repo/task):** " n_runs)
  print
}
' "$TEMPLATE" > "$OUTPUT.tmp"

# Replace placeholder rows in summary table using temp files
python3 - "$OUTPUT.tmp" "$OUTPUT" "$SUMMARY_FILE" "$REPO_FILE" "$TASK_FILE" << 'PYEOF'
import sys, re

tmp_path, out_path, summary_file, repo_file, task_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

with open(tmp_path) as f:
    content = f.read()

with open(summary_file) as f:
    summary_rows = f.read()
with open(repo_file) as f:
    repo_rows = f.read()
with open(task_file) as f:
    task_rows = f.read()

# Replace placeholder rows in Summary Table
content = re.sub(
    r'\| baseline \| XXXXX \| XXXXX \| — \|\n\| cmm-cold \| XXXXX \| XXXXX \| \+X% / −X% \|\n\| cmm-cache \| XXXXX \| XXXXX \| \+X% / −X% \|\n\| ctx \| XXXXX \| XXXXX \| \+X% / −X% \|\n\| cmm\+ctx-cold \| XXXXX \| XXXXX \| \+X% / −X% \|\n\| cmm\+ctx-cache \| XXXXX \| XXXXX \| \+X% / −X% \|',
    summary_rows.rstrip('\n'),
    content
)

# Replace per-repo placeholder rows
content = re.sub(
    r'\| expressjs/express \| XXXXX \| XXXXX \| XXXXX \| XXXXX \| XXXXX \| XXXXX \|.*?\| meilisearch/meilisearch \| XXXXX \| XXXXX \| XXXXX \| XXXXX \| XXXXX \| XXXXX \|',
    repo_rows.rstrip('\n'),
    content,
    flags=re.DOTALL
)

# Replace per-task placeholder rows
content = re.sub(
    r'\| 01-find-callers \| XXXXX \| XXXXX \| XXXXX \| XXXXX \| XXXXX \| XXXXX \|.*?\| 05-dead-code \| XXXXX \| XXXXX \| XXXXX \| XXXXX \| XXXXX \| XXXXX \|',
    task_rows.rstrip('\n'),
    content,
    flags=re.DOTALL
)

with open(out_path, 'w') as f:
    f.write(content)
PYEOF

rm -f "$OUTPUT.tmp" "$SUMMARY_FILE" "$REPO_FILE" "$TASK_FILE"

echo "Report saved to: $OUTPUT"
