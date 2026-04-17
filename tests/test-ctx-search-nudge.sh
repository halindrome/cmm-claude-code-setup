#!/bin/bash
# test-ctx-search-nudge.sh — Tests for ctx-search-nudge.sh PostToolUse advisory
# Usage: bash tests/test-ctx-search-nudge.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/ctx-search-nudge.sh"

PASS=0; FAIL=0

# _assert LABEL EXPECTED_EXIT EXPECTED_STDERR_CONTAINS EXPECT_STDERR_EMPTY JSON CWD_ENV
# EXPECTED_STDERR_CONTAINS: substring required on stderr (ignored if empty and EXPECT_EMPTY=1)
# EXPECT_STDERR_EMPTY: "1" means stderr must be empty; "0" means must contain EXPECTED_STDERR_CONTAINS
_assert() {
    local label="$1" expected_exit="$2" expected_contains="$3" expect_empty="$4" json="$5" env_prefix="${6:-}"
    local actual_exit=0 stderr_out=""
    if [ -n "$env_prefix" ]; then
        stderr_out=$(echo "$json" | env $env_prefix bash "$HOOK" 2>&1 >/dev/null) || actual_exit=$?
    else
        stderr_out=$(echo "$json" | bash "$HOOK" 2>&1 >/dev/null) || actual_exit=$?
    fi

    local ok=1
    if [ "$actual_exit" -ne "$expected_exit" ]; then
        ok=0
    fi
    if [ "$expect_empty" = "1" ]; then
        if [ -n "$stderr_out" ]; then
            ok=0
        fi
    else
        case "$stderr_out" in
            *"$expected_contains"*) : ;;
            *) ok=0 ;;
        esac
    fi

    if [ "$ok" -eq 1 ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (exit=$actual_exit expected=$expected_exit; stderr=[$stderr_out])"
        FAIL=$((FAIL+1))
    fi
}

# Bail out early if hook is missing
if [ ! -f "$HOOK" ]; then
    echo "NOTE: $HOOK does not exist yet. Run Plan 45-01 first."
    echo "Results: 0 passed, 0 failed (hook not yet available)"
    exit 0
fi

# --- Fixture Setup ---
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"; rm -f "/tmp/ctx-search-avail-${PH_YES:-x}" "/tmp/ctx-search-avail-${PH_NO:-x}"' EXIT

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
rm -f "/tmp/ctx-search-avail-${PH_YES}" "/tmp/ctx-search-avail-${PH_NO}"

# Common env to force absence-detection probe to use our fake home (suppress real user config)
ENV_NOCFG="HOME=$FAKE_HOME CLAUDE_CONFIG_DIR=$FAKE_HOME/.config/claude-code"

ADVISORY_TAG="[ctx-search-nudge]"

echo "--- Test a: ctx_execute with intent fires advisory ---"
_assert "a) ctx_execute intent='apache config' -> advisory with query echo" \
    0 'ctx_search(queries=["apache config"])' 0 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"intent\":\"apache config\"},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test b: ctx_execute with empty intent stays silent ---"
_assert "b) ctx_execute intent='' -> no advisory" \
    0 '' 1 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"intent\":\"\"},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test b2: ctx_execute with whitespace-only intent stays silent ---"
_assert "b2) ctx_execute intent='   ' -> no advisory" \
    0 '' 1 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"intent\":\"   \"},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test c: ctx_index fires unconditionally ---"
_assert "c) ctx_index (no intent) -> advisory" \
    0 "$ADVISORY_TAG" 0 \
    "{\"tool_name\":\"mcp__context-mode__ctx_index\",\"tool_input\":{},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test d: ctx_fetch_and_index fires unconditionally ---"
_assert "d) ctx_fetch_and_index -> advisory" \
    0 "$ADVISORY_TAG" 0 \
    "{\"tool_name\":\"mcp__context-mode__ctx_fetch_and_index\",\"tool_input\":{\"url\":\"https://example.com\"},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test e: ctx_batch_execute with one intented child fires with that intent ---"
_assert "e) ctx_batch_execute (one child intented) -> advisory echoes 'mr details'" \
    0 'ctx_search(queries=["mr details"])' 0 \
    "{\"tool_name\":\"mcp__context-mode__ctx_batch_execute\",\"tool_input\":{\"steps\":[{\"intent\":\"\"},{\"intent\":\"mr details\"}]},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test f: ctx_batch_execute with all empty intents stays silent ---"
_assert "f) ctx_batch_execute (all empty) -> no advisory" \
    0 '' 1 \
    "{\"tool_name\":\"mcp__context-mode__ctx_batch_execute\",\"tool_input\":{\"steps\":[{\"intent\":\"\"},{\"intent\":\"   \"}]},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test g: context-mode absent -> silent ---"
# Ensure cache for PROJ_NO is cleared, and suppress global fallback via fake HOME/CLAUDE_CONFIG_DIR
rm -f "/tmp/ctx-search-avail-${PH_NO}"
_assert "g) ctx_execute against project without context-mode -> silent" \
    0 '' 1 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"intent\":\"apache config\"},\"cwd\":\"$PROJ_NO\"}" \
    "$ENV_NOCFG"

echo "--- Test h: non-matching tool_name -> silent no-op ---"
_assert "h) Read tool -> no advisory" \
    0 '' 1 \
    "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/tmp/x\"},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test h2: ctx_search (retrieval side) -> silent no-op ---"
_assert "h2) ctx_search -> no advisory (retrieval, never nudged)" \
    0 '' 1 \
    "{\"tool_name\":\"mcp__context-mode__ctx_search\",\"tool_input\":{\"queries\":[\"apache config\"]},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test h3: ctx_stats (status/query tool) -> silent no-op ---"
_assert "h3) ctx_stats -> no advisory (status query, never nudged)" \
    0 '' 1 \
    "{\"tool_name\":\"mcp__context-mode__ctx_stats\",\"tool_input\":{},\"cwd\":\"$PROJ_YES\"}"

echo "--- Test i: empty stdin -> exit 0, silent ---"
_assert "i) empty stdin -> silent exit 0" \
    0 '' 1 \
    ""

echo "--- Test j: invalid JSON -> exit 0, silent ---"
_assert "j) invalid JSON -> silent exit 0" \
    0 '' 1 \
    "not json at all"

echo "--- Test k: missing tool_name -> exit 0, silent ---"
_assert "k) {} missing tool_name -> silent exit 0" \
    0 '' 1 \
    "{}"

echo "--- Test l: tool_input missing -> handled (ctx_execute with no tool_input -> silent) ---"
_assert "l) ctx_execute with no tool_input (empty intent) -> silent" \
    0 '' 1 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"cwd\":\"$PROJ_YES\"}"

echo ""
echo "=============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================================="
[ "$FAIL" -eq 0 ]
