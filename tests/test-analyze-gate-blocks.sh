#!/bin/bash
# test-analyze-gate-blocks.sh — Tests for scripts/analyze-gate-blocks.py
# Focus: block detection on a synthetic transcript + --share anonymization
# (no project names / usernames / paths leave the machine in share mode).
# Usage: bash tests/test-analyze-gate-blocks.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MINER="$SCRIPT_DIR/../scripts/analyze-gate-blocks.py"
PASS=0; FAIL=0
_ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
_bad()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- Fixture: a fake CLAUDE_CONFIG_DIR with one synthetic gate-block transcript ---
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SECRET="-Users-tester-Sources-secretclient"   # identifying slug we must never leak in --share
SESS="$TMP/projects/$SECRET"
mkdir -p "$SESS"
cat > "$SESS/session.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","usage":{"output_tokens":10},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"grep -r foo src/"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"PreToolUse:Bash hook error: [bash /repo/.claude/hooks/cmm-grep-nudge.sh]: BLOCKED: Use CMM tools instead of Bash navigation for code search."}]}}
{"type":"assistant","message":{"role":"assistant","usage":{"output_tokens":20},"content":[{"type":"text","text":"ok, switching approach"}]}}
EOF

run() { CLAUDE_CONFIG_DIR="$TMP" python3 "$MINER" "$@" 2>/dev/null; }

# --- Test 1: block detected and attributed to the right gate ---
OUT_PLAIN="$(run --all)"
echo "$OUT_PLAIN" | grep -q 'Blocks: 1 total' && _ok "Test 1: one block detected" || _bad "Test 1: block count"
echo "$OUT_PLAIN" | grep -q 'cmm-grep-nudge' && _ok "Test 2: attributed to cmm-grep-nudge" || _bad "Test 2: hook attribution"

# --- Test 3: non-share shows the de-prefixed (readable) project name ---
echo "$OUT_PLAIN" | grep -q 'secretclient' && _ok "Test 3: non-share shows readable name" || _bad "Test 3: de-prefixed name absent"

# --- Test 4: --share shows opaque ordinal, NOT the real name ---
OUT_SHARE="$(run --all --share)"
echo "$OUT_SHARE" | grep -q 'project-01' && _ok "Test 4: --share uses ordinal label" || _bad "Test 4: ordinal label missing"

# --- Test 5: --share leaks NOTHING identifying (name / username / path) ---
if echo "$OUT_SHARE" | grep -qiE 'secretclient|tester|/Users/|Sources'; then
  _bad "Test 5: --share leaked an identifying string"
else
  _ok "Test 5: --share output carries no project name / username / path"
fi

# --- Test 6: --share still reports the same aggregate block count ---
echo "$OUT_SHARE" | grep -q 'Blocks: 1 total' && _ok "Test 6: --share preserves aggregate metrics" || _bad "Test 6: aggregate metrics"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
