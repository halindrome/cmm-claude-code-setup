#!/bin/bash
# test-cmm-nudge-blocking.sh — Tests for cmm-nudge.sh soft per-file read budget
# Usage: bash tests/test-cmm-nudge-blocking.sh
# Exit: 0 = all pass, 1 = any failure
#
# cmm-nudge.sh is NON-BLOCKING (always exit 0). For code files (>=50 lines) in a
# CMM-configured repo it keeps a session-scoped per-file read counter and emits ONE
# advisory nudge (hookSpecificOutput.additionalContext on stdout) on the (BUDGET+1)th
# read of the same file. All exemptions still apply. These tests assert: exemptions
# stay silent+allowed, code-file reads are ALWAYS allowed (exit 0), and the nudge fires
# exactly once at the budget boundary, scoped per session.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/cmm-nudge.sh"
READ_BUDGET=3   # must match cmm-nudge.sh

PASS=0; FAIL=0

# _assert_exit LABEL EXPECTED_EXIT JSON [ENV_PREFIX]
_assert_exit() {
    local label="$1" expected="$2" json="$3" env_prefix="${4:-}"
    local actual=0
    if [ -n "$env_prefix" ]; then
        echo "$json" | env $env_prefix bash "$HOOK" >/dev/null 2>&1 || actual=$?
    else
        echo "$json" | bash "$HOOK" >/dev/null 2>&1 || actual=$?
    fi
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $label"; PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected exit $expected, got $actual)"; FAIL=$((FAIL+1))
    fi
}

# _assert_nudge LABEL EXPECT(yes|no) JSON — asserts exit 0 AND whether a nudge was emitted
_assert_nudge() {
    local label="$1" expect="$2" json="$3"
    local out rc=0
    out=$(echo "$json" | bash "$HOOK" 2>/dev/null) || rc=$?
    local has="no"
    case "$out" in *"times this session"*) has="yes" ;; esac
    if [ "$rc" -eq 0 ] && [ "$has" = "$expect" ]; then
        echo "PASS: $label"; PASS=$((PASS+1))
    else
        echo "FAIL: $label (exit=$rc nudge=$has; expected exit 0 nudge=$expect)"; FAIL=$((FAIL+1))
    fi
}

# --- Fixture Setup ---
TMPDIR_ROOT=$(mktemp -d)
# Clean any counter files from our controlled test sessions (and prior runs).
trap 'rm -rf "$TMPDIR_ROOT"; rm -f /tmp/cmm-reads-sb*-* /tmp/cmm-reads-nosession-*' EXIT
rm -f /tmp/cmm-reads-sb*-* /tmp/cmm-reads-nosession-* 2>/dev/null || true

# Primary test project: CMM installed, git repo
PROJ="$TMPDIR_ROOT/proj"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$PROJ/.mcp.json"

for i in $(seq 1 60); do echo "line $i"; done > "$PROJ/big.py"
for i in $(seq 1 60); do echo "// line $i"; done > "$PROJ/big.ts"
echo 'print("hello")' > "$PROJ/small.py"
echo '{}' > "$PROJ/config.json"
echo '# Some doc' > "$PROJ/some-doc.md"
echo '# CLAUDE.md' > "$PROJ/CLAUDE.md"
mkdir -p "$PROJ/.vbw-planning/phases/01"
for i in $(seq 1 60); do echo "plan line $i"; done > "$PROJ/.vbw-planning/phases/01/big-plan.py"
mkdir -p "$PROJ/.claude/hooks"
for i in $(seq 1 60); do echo "hook line $i"; done > "$PROJ/.claude/hooks/some-hook.sh"

# Second project: CMM NOT in .mcp.json
PROJ_NO_CMM="$TMPDIR_ROOT/proj-no-cmm"
mkdir -p "$PROJ_NO_CMM"
git -C "$PROJ_NO_CMM" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO_CMM/.mcp.json"
for i in $(seq 1 60); do echo "line $i"; done > "$PROJ_NO_CMM/big.py"

# Third project: No .mcp.json at all
PROJ_NO_MCP="$TMPDIR_ROOT/proj-no-mcp"
mkdir -p "$PROJ_NO_MCP"
git -C "$PROJ_NO_MCP" init -q
for i in $(seq 1 60); do echo "line $i"; done > "$PROJ_NO_MCP/big.py"

# Fake CLAUDE_CONFIG_DIR without CMM — suppresses global fallback
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{"hooks":{}}' > "$FAKE_CONFIG/settings.json"

# --- Exemptions: always allowed, never nudge (exit 0) ---
echo "--- Test 1: small .py allowed ---"
_assert_exit "Test 1: small .py allowed" 0 "{\"tool_input\":{\"file_path\":\"$PROJ/small.py\"}}"
echo "--- Test 2: config .json allowed ---"
_assert_exit "Test 2: config .json allowed" 0 "{\"tool_input\":{\"file_path\":\"$PROJ/config.json\"}}"
echo "--- Test 3: markdown .md allowed ---"
_assert_exit "Test 3: markdown allowed" 0 "{\"tool_input\":{\"file_path\":\"$PROJ/some-doc.md\"}}"
echo "--- Test 4: CLAUDE.md basename exempt ---"
_assert_exit "Test 4: CLAUDE.md exempt" 0 "{\"tool_input\":{\"file_path\":\"$PROJ/CLAUDE.md\"}}"
echo "--- Test 5: .vbw-planning path exempt ---"
_assert_exit "Test 5: planning path exempt" 0 "{\"tool_input\":{\"file_path\":\"$PROJ/.vbw-planning/phases/01/big-plan.py\"}}"
echo "--- Test 6: .claude path exempt ---"
_assert_exit "Test 6: .claude path exempt" 0 "{\"tool_input\":{\"file_path\":\"$PROJ/.claude/hooks/some-hook.sh\"}}"
echo "--- Test 7: CMM not in .mcp.json -> allowed ---"
_assert_exit "Test 7: no CMM in .mcp.json allowed" 0 "{\"tool_input\":{\"file_path\":\"$PROJ_NO_CMM/big.py\"}}" "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"
echo "--- Test 8: no .mcp.json at all -> allowed ---"
_assert_exit "Test 8: no .mcp.json allowed" 0 "{\"tool_input\":{\"file_path\":\"$PROJ_NO_MCP/big.py\"}}" "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"
echo "--- Test 9: non-existent file allowed ---"
_assert_exit "Test 9: non-existent allowed" 0 "{\"tool_input\":{\"file_path\":\"$PROJ/does-not-exist.py\"}}"
echo "--- Test 10: '# cmm-exempt' marker allowed ---"
_assert_exit "Test 10: cmm-exempt allowed" 0 "{\"tool_input\":{\"file_path\":\"$PROJ/big.py # cmm-exempt\"}}"

# --- Code-file reads are ALWAYS allowed now (former hard-block cases -> exit 0) ---
echo "--- Test 11: large .py allowed (no hard block) ---"
_assert_exit "Test 11: large .py allowed" 0 "{\"session_id\":\"sb11\",\"tool_input\":{\"file_path\":\"$PROJ/big.py\"}}"
echo "--- Test 12: large .ts allowed (no hard block) ---"
_assert_exit "Test 12: large .ts allowed" 0 "{\"session_id\":\"sb12\",\"tool_input\":{\"file_path\":\"$PROJ/big.ts\"}}"
echo "--- Test 13: top-level file_path fallback allowed ---"
_assert_exit "Test 13: top-level file_path allowed" 0 "{\"session_id\":\"sb13\",\"file_path\":\"$PROJ/big.py\"}"
echo "--- Test 14: offset+limit >100 allowed ---"
_assert_exit "Test 14: large offset+limit allowed" 0 "{\"session_id\":\"sb14\",\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":0,\"limit\":500}}"
echo "--- Test 15: offset-only allowed ---"
_assert_exit "Test 15: offset-only allowed" 0 "{\"session_id\":\"sb15\",\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":10}}"
echo "--- Test 16: limit-only allowed ---"
_assert_exit "Test 16: limit-only allowed" 0 "{\"session_id\":\"sb16\",\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"limit\":20}}"

# --- Per-file soft budget: silent under budget, ONE nudge at BUDGET+1, silent after ---
BUDGET_JSON="{\"session_id\":\"sbbudget\",\"tool_input\":{\"file_path\":\"$PROJ/big.py\"}}"
rm -f /tmp/cmm-reads-sbbudget-* 2>/dev/null || true
echo "--- Test 17: reads 1..BUDGET stay silent ---"
silent_ok=yes
for n in $(seq 1 "$READ_BUDGET"); do
    out=$(echo "$BUDGET_JSON" | bash "$HOOK" 2>/dev/null) || true
    case "$out" in *"times this session"*) silent_ok=no ;; esac
done
if [ "$silent_ok" = yes ]; then echo "PASS: Test 17: first $READ_BUDGET reads silent"; PASS=$((PASS+1));
else echo "FAIL: Test 17: a read under budget emitted a nudge"; FAIL=$((FAIL+1)); fi

echo "--- Test 18: (BUDGET+1)th read emits the nudge ---"
_assert_nudge "Test 18: nudge at budget boundary" yes "$BUDGET_JSON"

echo "--- Test 19: reads beyond BUDGET+1 are silent again ---"
_assert_nudge "Test 19: silent after nudging once" no "$BUDGET_JSON"

echo "--- Test 20: budget is per-session (fresh session -> silent) ---"
rm -f /tmp/cmm-reads-sbfresh-* 2>/dev/null || true
_assert_nudge "Test 20: fresh session first read silent" no \
    "{\"session_id\":\"sbfresh\",\"tool_input\":{\"file_path\":\"$PROJ/big.py\"}}"

echo "--- Test 21: '# cmm-exempt' never nudges even when repeated ---"
exempt_ok=yes
for n in 1 2 3 4 5; do
    out=$(echo "{\"session_id\":\"sbexempt\",\"tool_input\":{\"file_path\":\"$PROJ/big.py # cmm-exempt\"}}" | bash "$HOOK" 2>/dev/null) || true
    case "$out" in *"times this session"*) exempt_ok=no ;; esac
done
if [ "$exempt_ok" = yes ]; then echo "PASS: Test 21: cmm-exempt never nudges"; PASS=$((PASS+1));
else echo "FAIL: Test 21: cmm-exempt path emitted a nudge"; FAIL=$((FAIL+1)); fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
