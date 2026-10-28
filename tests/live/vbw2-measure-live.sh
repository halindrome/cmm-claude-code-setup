#!/bin/bash
# vbw2-measure-live.sh — live proof that make measure sees CMM use in VBW 2 agents (R1)
# Not part of `make test` (it reads this machine's Claude Code transcripts).
# Runs scripts/analyze-enforcement.py 30 (what `make measure DAYS=30` runs) and
# requires a VBW 2 WORKFLOW AGENTS row for this repo's transcripts with CMM>0.
# No VBW 2 workflow transcript of this repo in the last 30 days -> SKIP.
# Usage: bash tests/live/vbw2-measure-live.sh
# Exit: 0 = pass (or skip), 1 = failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
COMMON="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$REPO/.git")"
ROOT="$(cd "$COMMON/.." && pwd -P)"
SLUG="$(printf '%s' "$ROOT" | sed 's/[^A-Za-z0-9]/-/g')"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude-code}"

if [ -z "$(find "$CFG/projects/$SLUG" -path '*/subagents/workflows/*' -name 'agent-*.meta.json' -mtime -30 -exec grep -l '"agentType": *"vbw:' {} + 2>/dev/null | head -1)" ]; then
    echo "SKIP: no VBW 2 workflow transcripts for $SLUG in the last 30 days"
    exit 0
fi

OUT="$(python3 "$REPO/scripts/analyze-enforcement.py" 30 2>&1)" || {
    echo "FAIL: analyze-enforcement.py exited non-zero"
    exit 1
}
printf '%s\n' "$OUT" | SLUG="$SLUG" python3 -c '
import os, re, sys
slug = os.environ["SLUG"]
lines = sys.stdin.read().splitlines()
start = next((i for i, l in enumerate(lines) if "VBW 2 WORKFLOW AGENTS" in l), None)
if start is None:
    print("FAIL: no VBW 2 WORKFLOW AGENTS section"); sys.exit(1)
hits = []
for l in lines[start + 1:]:
    if re.match(r"^\s*[0-9]+[a-z]?\. ", l):
        break
    m = re.search(r"(?<![\w-])CMM=(\d+)", l)
    if slug in l and re.search(r"(^|\s)vbw:[a-z]+", l) and m and int(m.group(1)) > 0:
        hits.append(l.strip())
if not hits:
    print(f"FAIL: no VBW 2 agent row for {slug} with CMM>0"); sys.exit(1)
for h in hits:
    print("PASS: " + h)'
