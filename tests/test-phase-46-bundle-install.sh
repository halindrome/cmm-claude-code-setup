#!/bin/bash
# test-phase-46-bundle-install.sh — Integration smoke test for phase-46 bundle install
# Verifies that setup.sh --project installs the two new phase-46 project hooks
# (grep-cmm-gate.sh, ctx-execute-cmm-nudge.sh) into .claude/hooks/, registers
# both in .claude/settings.json under hooks.PreToolUse, and is idempotent on
# re-run. Also verifies the ctx-execute-enforcer.sh CMM-search suffix is
# present in the installed copy.
# Usage: bash tests/test-phase-46-bundle-install.sh
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
SCRATCH=$(mktemp -d -t cmm-phase46-XXXXXX)
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

# --- Artifacts exist and are executable ---
_assert "grep-cmm-gate.sh installed" test -f ".claude/hooks/grep-cmm-gate.sh"
_assert "grep-cmm-gate.sh is executable" test -x ".claude/hooks/grep-cmm-gate.sh"
_assert "ctx-execute-cmm-nudge.sh installed" test -f ".claude/hooks/ctx-execute-cmm-nudge.sh"
_assert "ctx-execute-cmm-nudge.sh is executable" test -x ".claude/hooks/ctx-execute-cmm-nudge.sh"
_assert "ctx-execute-enforcer.sh installed" test -f ".claude/hooks/ctx-execute-enforcer.sh"

# --- CMM-search suffix present in installed enforcer ---
_assert "ctx-execute-enforcer.sh contains CMM-search suffix" \
    grep -qF 'search_code / search_graph (CMM)' .claude/hooks/ctx-execute-enforcer.sh

# --- settings.json is valid JSON ---
_assert "settings.json is valid JSON" python3 -m json.tool .claude/settings.json

# --- Hook registrations present in settings.json ---
_assert "grep-cmm-gate registered under PreToolUse with matcher Grep" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PreToolUse', [])
found = any(
    entry.get('matcher', '') == 'Grep' and
    any('grep-cmm-gate.sh' in h.get('command', '') for h in entry.get('hooks', []))
    for entry in entries
)
sys.exit(0 if found else 1)
"

_assert "ctx-execute-cmm-nudge registered under PreToolUse with matcher mcp__context-mode__ctx_execute" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PreToolUse', [])
found = any(
    entry.get('matcher', '') == 'mcp__context-mode__ctx_execute' and
    any('ctx-execute-cmm-nudge.sh' in h.get('command', '') for h in entry.get('hooks', []))
    for entry in entries
)
sys.exit(0 if found else 1)
"

# --- Existing soft-advisory cmm-grep-nudge must still be registered (coexistence) ---
_assert "cmm-grep-nudge.sh still registered (coexists with grep-cmm-gate)" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PreToolUse', [])
found = any(
    any('cmm-grep-nudge.sh' in h.get('command', '') for h in entry.get('hooks', []))
    for entry in entries
)
sys.exit(0 if found else 1)
"

# --- No duplicate matcher-command pairs ---
_assert "no duplicate grep-cmm-gate entries" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PreToolUse', [])
count = sum(
    1 for entry in entries
    for h in entry.get('hooks', [])
    if 'grep-cmm-gate.sh' in h.get('command', '')
)
sys.exit(0 if count == 1 else 1)
"

_assert "no duplicate ctx-execute-cmm-nudge entries" \
    python3 -c "
import json, sys
with open('.claude/settings.json') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PreToolUse', [])
count = sum(
    1 for entry in entries
    for h in entry.get('hooks', [])
    if 'ctx-execute-cmm-nudge.sh' in h.get('command', '')
)
sys.exit(0 if count == 1 else 1)
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
for h in grep-cmm-gate.sh ctx-execute-cmm-nudge.sh; do
    if cmp -s "$REPO_ROOT/hooks/project/$h" ".claude/hooks/$h"; then
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
