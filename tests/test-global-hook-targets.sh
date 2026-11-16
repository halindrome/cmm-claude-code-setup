#!/bin/bash
# test-global-hook-targets.sh — every hook --global registers must exist on disk.
#   - each `${CLAUDE_CONFIG_DIR}/hooks/<x>` command in global settings.json resolves
#     to a file setup.sh installed (a missing one exits 127 on every matching call)
#   - a re-run removes the retired track-cmm/ctx-calls.sh global entries that
#     earlier releases registered without installing the scripts
#
# Run: bash tests/test-global-hook-targets.sh
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_ROOT/setup.sh"
PASS=0; FAIL=0
_pass(){ echo "PASS: $1"; PASS=$((PASS+1)); }
_fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Prints one line per registered ${CLAUDE_CONFIG_DIR}/hooks/<x> target.
_targets(){ python3 - "$1" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
for groups in d.get("hooks", {}).values():
    for g in groups:
        for h in g.get("hooks", []):
            m = re.search(r'\$\{CLAUDE_CONFIG_DIR\}/(hooks/[^"\s]+)', h.get("command", ""))
            if m: print(m.group(1))
PY
}

T=$(mktemp -d); CFG="$T/cfg"; mkdir -p "$CFG"
trap 'rm -rf "$T"' EXIT

# Seed the broken entries a pre-fix --global left behind.
cat > "$CFG/settings.json" <<'JSON'
{"hooks": {"PostToolUse": [
  {"matcher": "mcp__codebase-memory-mcp__*",
   "hooks": [{"type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/track-cmm-calls.sh\""}]},
  {"matcher": "mcp__plugin_context-mode_context-mode__*|mcp__context-mode__*",
   "hooks": [{"type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/track-ctx-calls.sh\""}]},
  {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo user-hook"}]}
]}}
JSON

CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" --global --yes --skip-mcp-check --skip-statusline >/dev/null 2>&1 || true
GF="$CFG/settings.json"

n=0
while IFS= read -r rel; do
    n=$((n+1))
    if [ -f "$CFG/$rel" ]; then _pass "registered $rel is installed"
    else _fail "registered $rel is NOT installed (exit 127 on every call)"; fi
done < <(_targets "$GF")
[ "$n" -gt 0 ] && _pass "global install registered $n hook targets" || _fail "no global hook targets found"

grep -q 'track-cmm-calls.sh' "$GF" && _fail "retired track-cmm-calls.sh entry survived" || _pass "retired track-cmm-calls.sh entry removed"
grep -q 'track-ctx-calls.sh' "$GF" && _fail "retired track-ctx-calls.sh entry survived" || _pass "retired track-ctx-calls.sh entry removed"
grep -q 'echo user-hook' "$GF" && _pass "unrelated user hook kept" || _fail "unrelated user hook was dropped"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
