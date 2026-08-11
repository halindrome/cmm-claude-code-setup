#!/bin/bash
# test-zero-vbw-footprint.sh — verifies that a project install with VBW ABSENT
# leaves no VBW footprint: the agent-override-generate.sh SessionStart entry is
# not registered, VBW-only hook files are not installed, and VBW-only files left
# by a PRIOR VBW-enabled install are moved aside into the reversible backup dir.
#
# This covers the file-deleting / JSON-mutating half of setup.sh's zero-VBW path
# (install_project, `if [ "$_vbw_present" != true ]`), which otherwise ships with
# no behavioural coverage at all.
#
# Run: bash tests/test-zero-vbw-footprint.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SETUP="$SCRIPT_DIR/setup.sh"
PASS=0
FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
_chk()  { if eval "$2"; then _pass "$1"; else _fail "$1"; fi; }

# A scratch HOME + CLAUDE_CONFIG_DIR with no plugin registry makes
# vbw_is_available() resolve to "absent" — the condition under test.
T=$(mktemp -d)
FAKE_HOME="$T/home"
FAKE_CONF="$T/home/.config/claude-code"
PROJ="$T/proj"
mkdir -p "$FAKE_CONF/plugins" "$PROJ/.claude/hooks/lib"

# Stale artifacts from a hypothetical earlier VBW-enabled install.
echo '#!/bin/bash' > "$PROJ/.claude/hooks/agent-override-generate.sh"
echo '#!/bin/bash' > "$PROJ/.claude/hooks/lib/vbw-source.sh"

( cd "$PROJ" && echo n | HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_CONF" \
    bash "$SETUP" --project --yes --skip-mcp-check --skip-statusline --no-migrate \
) > "$T/setup.out" 2>&1

echo "--- zero-VBW project install ---"
_chk "install produced settings.json" \
     '[ -f "$PROJ/.claude/settings.json" ]'
_chk "settings.json is valid JSON" \
     'python3 -m json.tool "$PROJ/.claude/settings.json" >/dev/null 2>&1'
_chk "no agent-override-generate.sh hook registration" \
     '! grep -q agent-override-generate.sh "$PROJ/.claude/settings.json"'
_chk "stale agent-override-generate.sh moved out of hooks/" \
     '[ ! -e "$PROJ/.claude/hooks/agent-override-generate.sh" ]'
_chk "stale vbw-source.sh moved out of hooks/lib/" \
     '[ ! -e "$PROJ/.claude/hooks/lib/vbw-source.sh" ]'
_chk "stale agent-override-generate.sh is recoverable from backup" \
     '[ -f "$PROJ/.claude/.cmm-setup/vbw-agents.bak/hooks/agent-override-generate.sh" ]'
_chk "stale vbw-source.sh is recoverable from backup" \
     '[ -f "$PROJ/.claude/.cmm-setup/vbw-agents.bak/hooks/lib/vbw-source.sh" ]'
_chk "no VBW agent deltas written" \
     '! ls "$PROJ"/.claude/agents-delta/vbw-*.md >/dev/null 2>&1'
_chk "CMM hooks still installed (install did not just no-op)" \
     '[ -f "$PROJ/.claude/hooks/session-gate.sh" ]'

rm -rf "$T"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
