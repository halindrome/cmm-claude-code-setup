#!/bin/bash
# test-phase-45-bundle-install.sh — Integration smoke test for phase-45 bundle install
# Verifies that setup.sh --project installs the three phase-45 artifacts
# (ctx-search-nudge.sh, subagent-ctx-startup.sh, ctx-rules.md) into .claude/,
# registers both hooks in .claude/settings.json, and is idempotent on re-run.
# Usage: bash tests/test-phase-45-bundle-install.sh
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
SCRATCH=$(mktemp -d -t cmm-phase45-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

cd "$SCRATCH"

# Minimal git repo so setup.sh --project has a project root to anchor to.
git init -q
git commit --allow-empty -q -m "init"

# Run install (non-interactive, skip MCP availability check — setup.sh does not
# require context-mode to be reachable in order to copy hooks + register them).
echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project first run exited non-zero"
    exit 1
}

# --- Artifacts exist ---
_assert "ctx-search-nudge.sh installed" test -f ".claude/hooks/ctx-search-nudge.sh"
_assert "ctx-search-nudge.sh is executable" test -x ".claude/hooks/ctx-search-nudge.sh"
_assert "subagent-ctx-startup.sh installed" test -f ".claude/hooks/subagent-ctx-startup.sh"
_assert "subagent-ctx-startup.sh is executable" test -x ".claude/hooks/subagent-ctx-startup.sh"
_assert "ctx-rules.md installed" test -f ".claude/rules/ctx-rules.md"

# --- Hook registrations present in settings.json ---
_assert "ctx-search-nudge registered under PostToolUse" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PostToolUse', [])
found = any(
    any('ctx-search-nudge.sh' in h.get('command', '') for h in entry.get('hooks', []))
    for entry in entries
)
sys.exit(0 if found else 1)
"

_assert "subagent-ctx-startup registered under SubagentStart" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('SubagentStart', [])
found = any(
    any('subagent-ctx-startup.sh' in h.get('command', '') for h in entry.get('hooks', []))
    for entry in entries
)
sys.exit(0 if found else 1)
"

_assert "ctx-search-nudge matcher targets the four indexing tools" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
expected = 'mcp__context-mode__ctx_execute|mcp__context-mode__ctx_index|mcp__context-mode__ctx_fetch_and_index|mcp__context-mode__ctx_batch_execute'
entries = data.get('hooks', {}).get('PostToolUse', [])
found = any(
    entry.get('matcher', '') == expected and
    any('ctx-search-nudge.sh' in h.get('command', '') for h in entry.get('hooks', []))
    for entry in entries
)
sys.exit(0 if found else 1)
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

# Both hook files should also be unchanged on second run.
for h in ctx-search-nudge.sh subagent-ctx-startup.sh; do
    # Compare against source
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
