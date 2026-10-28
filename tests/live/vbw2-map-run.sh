#!/bin/bash
# vbw2-map-run.sh — live proof that VBW 2 mapping uses CMM (R11)
# Not part of `make test` (it reads this machine's Claude Code transcripts).
#  1. .vbw/map.md has, in one of the mapping.js map sections (Stack and
#     commands, Structure, Conventions, Tests, Risks), the CMM project of this
#     repo and the cmm-query.sh wrapper command for the live graph.
#  2. The latest recorded `vbw map` run of this repo (a workflow whose journal
#     starts the five scout angles): the structure scout makes at least one
#     wrapper (or `codebase-memory-mcp cli`) Bash call. Other angles need no CMM
#     call, and redirect of code search is proven by C6 (D9).
#     No mapping run on this machine -> SKIP (visible), not a failure.
# Precondition: re-run setup.sh --project here (wrapper installed), then /vbw:map.
# Usage: bash tests/live/vbw2-map-run.sh
# Exit: 0 = pass (or skip of part 2), 1 = failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
# The main checkout (vbw prove runs this in a worktree of it).
COMMON="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$REPO/.git")"
ROOT="$(cd "$COMMON/.." && pwd -P)"
PROJ="$(PROJECT_ROOT="$ROOT" bash -c 'source "$0"; cmm_project_name' "$REPO/hooks/lib/cmm-registered.sh")"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude-code}"

MAP="$REPO/.vbw/map.md" PROJ="$PROJ" ROOT="$ROOT" CFG="$CFG" python3 - <<'PY'
import glob, json, os, re, sys

fails = []
proj = os.environ["PROJ"]
sections = ("stack and commands", "structure", "conventions", "tests", "risks")

try:
    text = open(os.environ["MAP"]).read()
except OSError:
    text = ""
found = None
for block in re.split(r"(?m)^(?=## )", text):
    head = block.splitlines()[0][3:].strip().lower() if block.startswith("## ") else ""
    if head.startswith(sections) and "cmm-query.sh" in block and proj in block:
        found = head
if found:
    print(f"PASS: .vbw/map.md section '{found}' names CMM project {proj} and the wrapper")
else:
    fails.append(f".vbw/map.md has no map section naming CMM project {proj} and cmm-query.sh")

slug = re.sub(r"[^A-Za-z0-9]", "-", os.environ["ROOT"])
angles = ["scout stack", "scout structure", "scout conventions", "scout tests", "scout risks"]
runs = []
for j in glob.glob(os.path.join(os.environ["CFG"], "projects", slug, "*", "subagents", "workflows", "*", "journal.jsonl")):
    labels = {}
    for line in open(j, errors="replace"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("type") == "started" and r.get("label") in angles:
            labels[r["label"]] = r.get("agentId")
    if len(labels) == len(angles):
        runs.append((os.path.getmtime(j), os.path.dirname(j), labels))
if not runs:
    print(f"SKIP: no recorded vbw map run for {slug} on this machine")
else:
    _, d, labels = max(runs)
    cmm = re.compile(r"cmm-query\.sh|codebase-memory-mcp\s+cli\b")
    a = "scout structure"
    n = 0
    for line in open(os.path.join(d, f"agent-{labels[a]}.jsonl"), errors="replace"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        for b in ((r.get("message") or {}).get("content") or []):
            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Bash" \
                    and cmm.search(str((b.get("input") or {}).get("command", ""))):
                n += 1
    if n:
        print(f"PASS: {os.path.basename(d)} {a}: {n} wrapper CMM call(s)")
    else:
        fails.append(f"{os.path.basename(d)} {a}: no wrapper CMM call")
for f in fails:
    print("FAIL: " + f)
sys.exit(1 if fails else 0)
PY
