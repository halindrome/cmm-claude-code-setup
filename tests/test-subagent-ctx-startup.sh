#!/bin/bash
# test-subagent-ctx-startup.sh — Tests for subagent-ctx-startup.sh SubagentStart injector
# Usage: bash tests/test-subagent-ctx-startup.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/subagent-ctx-startup.sh"

PASS=0; FAIL=0

# _assert LABEL EXPECTED_EXIT EXPECTED_STDOUT_CONTAINS EXPECT_STDOUT_EMPTY JSON ENV_PREFIX
# EXPECTED_STDOUT_CONTAINS: substring required on stdout (ignored when EXPECT_EMPTY=1)
# EXPECT_STDOUT_EMPTY: "1" means stdout must be empty; "0" means must contain EXPECTED_STDOUT_CONTAINS
_assert() {
    local label="$1" expected_exit="$2" expected_contains="$3" expect_empty="$4" json="$5" env_prefix="${6:-}"
    local actual_exit=0 stdout_out=""
    if [ -n "$env_prefix" ]; then
        stdout_out=$(echo "$json" | env $env_prefix bash "$HOOK" 2>/dev/null) || actual_exit=$?
    else
        stdout_out=$(echo "$json" | bash "$HOOK" 2>/dev/null) || actual_exit=$?
    fi

    local ok=1
    if [ "$actual_exit" -ne "$expected_exit" ]; then
        ok=0
    fi
    if [ "$expect_empty" = "1" ]; then
        if [ -n "$stdout_out" ]; then
            ok=0
        fi
    else
        case "$stdout_out" in
            *"$expected_contains"*) : ;;
            *) ok=0 ;;
        esac
    fi

    if [ "$ok" -eq 1 ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (exit=$actual_exit expected=$expected_exit; stdout=[$stdout_out])"
        FAIL=$((FAIL+1))
    fi
}

# Bail out early if hook is missing
if [ ! -f "$HOOK" ]; then
    echo "NOTE: $HOOK does not exist yet."
    echo "Results: 0 passed, 0 failed (hook not yet available)"
    exit 0
fi

# --- Fixture Setup ---
TMPDIR_ROOT=$(mktemp -d)

# Project with context-mode registered
PROJ_YES="$TMPDIR_ROOT/proj-with-ctx"
mkdir -p "$PROJ_YES"
git -C "$PROJ_YES" init -q
echo '{"mcpServers":{"context-mode":{"command":"npx"}}}' > "$PROJ_YES/.mcp.json"

# Project without context-mode
PROJ_NO="$TMPDIR_ROOT/proj-without-ctx"
mkdir -p "$PROJ_NO"
git -C "$PROJ_NO" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO/.mcp.json"

# Fake HOME + CLAUDE_CONFIG_DIR with no context-mode — suppresses global fallback
FAKE_HOME="$TMPDIR_ROOT/fake-home"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.config/claude-code"
echo '{"hooks":{}}' > "$FAKE_HOME/.claude/settings.json"
echo '{"hooks":{}}' > "$FAKE_HOME/.config/claude-code/settings.json"

# Compute PROJECT_HASH values the hook will use, so we can clear caches between runs
if command -v md5 >/dev/null 2>&1; then
    PH_YES="$(echo "$PROJ_YES" | md5 -q)"
    PH_NO="$(echo "$PROJ_NO" | md5 -q)"
else
    PH_YES="$(echo "$PROJ_YES" | md5sum | awk '{print $1}')"
    PH_NO="$(echo "$PROJ_NO" | md5sum | awk '{print $1}')"
fi
rm -f "/tmp/ctx-subagent-avail-${PH_YES}" "/tmp/ctx-subagent-avail-${PH_NO}"

trap 'rm -rf "$TMPDIR_ROOT"; rm -f "/tmp/ctx-subagent-avail-${PH_YES}" "/tmp/ctx-subagent-avail-${PH_NO}"' EXIT

# Common env to force absence-detection probe to use our fake home (suppress real user config)
ENV_NOCFG="HOME=$FAKE_HOME CLAUDE_CONFIG_DIR=$FAKE_HOME/.config/claude-code"

MARKER="[ctx-startup]"
TOOL="mcp__context-mode__ctx_stats"

echo "--- Test a: context-mode present -> stdout contains marker and names ctx_stats ---"
# Run once, check marker present
_assert "a1) context-mode present -> stdout contains $MARKER" \
    0 "$MARKER" 0 \
    "{\"cwd\":\"$PROJ_YES\"}"
# And names the ctx_stats MCP tool explicitly
_assert "a2) context-mode present -> stdout names $TOOL" \
    0 "$TOOL" 0 \
    "{\"cwd\":\"$PROJ_YES\"}"

echo "--- Test b: context-mode absent -> stdout empty, exit 0 ---"
# Ensure no cached avail=1 from a previous run
rm -f "/tmp/ctx-subagent-avail-${PH_NO}"
_assert "b) context-mode absent -> stdout empty" \
    0 '' 1 \
    "{\"cwd\":\"$PROJ_NO\"}" \
    "$ENV_NOCFG"

echo "--- Test c: empty stdin -> exit 0, silent ---"
_assert "c) empty stdin -> silent exit 0" \
    0 '' 1 \
    ""

echo "--- Test d: invalid JSON -> exit 0, silent ---"
_assert "d) invalid JSON -> silent exit 0" \
    0 '' 1 \
    "not json at all"

# --- Extra robustness: missing cwd field -> silent exit 0 ---
echo "--- Test e (bonus): missing cwd -> silent ---"
_assert "e) {} missing cwd -> silent exit 0" \
    0 '' 1 \
    "{}"

echo ""
echo "=============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================================="
[ "$FAIL" -eq 0 ]
