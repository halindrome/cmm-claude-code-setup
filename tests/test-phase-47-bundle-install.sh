#!/bin/bash
# test-phase-47-bundle-install.sh — Integration smoke test for phase-47 bundle install
# Verifies that setup.sh --project installs the two new phase-47 global hooks
# (ctx-annotate-nudge.sh, cmm-orient-nudge.sh), registers both in
# .claude/settings.json under PostToolUse, retires ctx-search-nudge.sh
# (must NOT be installed, must NOT be registered), and is idempotent on
# re-run.
# Usage: bash tests/test-phase-47-bundle-install.sh
# Exit: 0 = all pass, 1 = any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PASS=0; FAIL=0

_assert() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label"
        FAIL=$((FAIL+1))
    fi
}

# Create scratch project dir (temp dir cleaned on exit).
SCRATCH=$(mktemp -d -t cmm-phase47-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

cd "$SCRATCH"

# Minimal git repo so setup.sh --project has a project root to anchor to.
git init -q
git commit --allow-empty -q -m "init"

# Run install (non-interactive, skip MCP availability check).
echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project first run exited non-zero"
    exit 1
}

# --- New hooks exist and are executable ---
_assert "ctx-annotate-nudge.sh installed" test -f ".claude/hooks/ctx-annotate-nudge.sh"
_assert "ctx-annotate-nudge.sh is executable" test -x ".claude/hooks/ctx-annotate-nudge.sh"
_assert "cmm-orient-nudge.sh installed" test -f ".claude/hooks/cmm-orient-nudge.sh"
_assert "cmm-orient-nudge.sh is executable" test -x ".claude/hooks/cmm-orient-nudge.sh"

# --- Retired hook is absent ---
_assert "ctx-search-nudge.sh NOT installed (retired)" \
    bash -c 'test ! -e ".claude/hooks/ctx-search-nudge.sh"'

# --- settings.json is valid JSON ---
_assert "settings.json is valid JSON" python3 -m json.tool .claude/settings.json

# --- ctx-annotate-nudge registered with the expected matcher ---
_assert "ctx-annotate-nudge registered under PostToolUse with ctx_* matcher" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
expected = 'mcp__context-mode__ctx_execute|mcp__context-mode__ctx_search|mcp__context-mode__ctx_index|mcp__context-mode__ctx_fetch_and_index'
entries = data.get('hooks', {}).get('PostToolUse', [])
found = any(
    entry.get('matcher', '') == expected and
    any('ctx-annotate-nudge.sh' in h.get('command', '') for h in entry.get('hooks', []))
    for entry in entries
)
sys.exit(0 if found else 1)
"

# --- cmm-orient-nudge registered with search_graph matcher ---
_assert "cmm-orient-nudge registered under PostToolUse with search_graph matcher" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PostToolUse', [])
found = any(
    entry.get('matcher', '') == 'mcp__codebase-memory-mcp__search_graph' and
    any('cmm-orient-nudge.sh' in h.get('command', '') for h in entry.get('hooks', []))
    for entry in entries
)
sys.exit(0 if found else 1)
"

# --- No ctx-search-nudge entry anywhere in settings.json ---
_assert "ctx-search-nudge NOT registered in settings.json" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
found = False
for entries in data.get('hooks', {}).values():
    for entry in entries:
        for h in entry.get('hooks', []):
            if 'ctx-search-nudge' in h.get('command', ''):
                found = True
sys.exit(1 if found else 0)
"

# --- No duplicate matcher-command pairs for the new hooks ---
_assert "no duplicate ctx-annotate-nudge entries" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
count = sum(
    1
    for entries in data.get('hooks', {}).values()
    for entry in entries
    for h in entry.get('hooks', [])
    if 'ctx-annotate-nudge.sh' in h.get('command', '')
)
sys.exit(0 if count == 1 else 1)
"

_assert "no duplicate cmm-orient-nudge entries" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
count = sum(
    1
    for entries in data.get('hooks', {}).values()
    for entry in entries
    for h in entry.get('hooks', [])
    if 'cmm-orient-nudge.sh' in h.get('command', '')
)
sys.exit(0 if count == 1 else 1)
"

# --- Deprecated hook purge: pre-seed ctx-search-nudge.sh into .claude/hooks/
#     and a matching settings.json entry, then re-run setup.sh and confirm both
#     are removed. This exercises the deprecated_hooks code path in setup.sh. ---
echo "#!/bin/bash" > .claude/hooks/ctx-search-nudge.sh
chmod +x .claude/hooks/ctx-search-nudge.sh
python3 - <<'PY'
import json
with open('.claude/settings.json') as f:
    data = json.load(f)
data.setdefault('hooks', {}).setdefault('PostToolUse', []).append({
    "matcher": "mcp__context-mode__ctx_execute",
    "hooks": [{"type": "command", "command": "bash .claude/hooks/ctx-search-nudge.sh"}]
})
with open('.claude/settings.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project purge-rerun exited non-zero"
    FAIL=$((FAIL+1))
}

_assert "ctx-search-nudge.sh purged after re-install" \
    bash -c 'test ! -e ".claude/hooks/ctx-search-nudge.sh"'

_assert "ctx-search-nudge settings entry pruned after re-install" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
found = False
for entries in data.get('hooks', {}).values():
    for entry in entries:
        for h in entry.get('hooks', []):
            if 'ctx-search-nudge' in h.get('command', ''):
                found = True
sys.exit(1 if found else 0)
"

# --- Idempotency: snapshot settings.json, re-run setup, diff ---
cp .claude/settings.json .claude/settings.json.snap1
sha_before=$(shasum .claude/settings.json.snap1 | awk '{print $1}')

echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project second run exited non-zero"
    FAIL=$((FAIL+1))
}
sha_after=$(shasum .claude/settings.json | awk '{print $1}')

if [ "$sha_before" = "$sha_after" ]; then
    echo "PASS: settings.json byte-identical after second run (idempotent)"
    PASS=$((PASS+1))
else
    echo "FAIL: settings.json changed on second run (not idempotent)"
    diff .claude/settings.json.snap1 .claude/settings.json || true
    FAIL=$((FAIL+1))
fi

# New hook files should be unchanged on second run.
for h in ctx-annotate-nudge.sh cmm-orient-nudge.sh; do
    if cmp -s "$REPO_ROOT/hooks/global/$h" ".claude/hooks/$h"; then
        echo "PASS: .claude/hooks/$h matches source"
        PASS=$((PASS+1))
    else
        echo "FAIL: .claude/hooks/$h differs from source"
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
