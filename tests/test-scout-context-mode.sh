#!/bin/bash
# test-scout-context-mode.sh — Verify Scout agent body contains Context Mode integration sections
# Usage: bash tests/test-scout-context-mode.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCOUT_FILE="$SCRIPT_DIR/../agents/vbw-scout.md"

PASS=0; FAIL=0

_assert_contains() {
    local label="$1" pattern="$2"
    if grep -q "$pattern" "$SCOUT_FILE" 2>/dev/null; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (pattern not found: $pattern)"
        FAIL=$((FAIL+1))
    fi
}

_assert_not_contains() {
    local label="$1" pattern="$2"
    if grep -q "$pattern" "$SCOUT_FILE" 2>/dev/null; then
        echo "FAIL: $label (pattern should NOT be present: $pattern)"
        FAIL=$((FAIL+1))
    else
        echo "PASS: $label"
        PASS=$((PASS+1))
    fi
}

# Bail out early if scout file doesn't exist yet
if [ ! -f "$SCOUT_FILE" ]; then
    echo ""
    echo "NOTE: $SCOUT_FILE does not exist yet."
    echo "This test suite requires agents/vbw-scout.md to be present."
    echo ""
    echo "Results: $PASS passed, $FAIL failed (scout file not available)"
    exit 0
fi

# --- Positive content tests: Context Mode sections ---
echo "--- Context Mode section headers ---"

_assert_contains "Context Mode Web Fetch section header exists" \
    "## Context Mode Web Fetch"

_assert_contains "Research Output Indexing section header exists" \
    "## Research Output Indexing"

# --- Positive content tests: tool references ---
echo ""
echo "--- Context Mode tool references ---"

_assert_contains "ctx_fetch_and_index tool reference" \
    "ctx_fetch_and_index"

_assert_contains "fully-qualified ctx_fetch_and_index tool name" \
    "mcp__context-mode__ctx_fetch_and_index"

_assert_contains "ctx_index tool reference" \
    "ctx_index"

_assert_contains "fully-qualified ctx_index tool name" \
    "mcp__context-mode__ctx_index"

_assert_contains "ctx_search referenced for querying indexed content" \
    "ctx_search"

# --- Positive content tests: fallback and delimiters ---
echo ""
echo "--- Fallback language and delimiter comments ---"

_assert_contains "WebFetch fallback language present" \
    "WebFetch"

_assert_contains "Extension start delimiter comment" \
    "cmm-claude-code-setup: Context Mode extensions"

_assert_contains "Extension end delimiter comment" \
    "end cmm-claude-code-setup extensions"

# --- Negative and structural tests ---
echo ""
echo "--- Negative and structural tests ---"

_assert_contains "disallowedTools includes Bash" \
    "disallowedTools:.*Bash"

_assert_not_contains "ctx_execute should NOT be in Scout body" \
    "ctx_execute"

_assert_not_contains "ctx_batch_execute should NOT be in Scout body (requires Bash)" \
    "ctx_batch_execute"

_assert_contains "MCP Tool Usage section still exists" \
    "## MCP Tool Usage"

_assert_contains "External Data Validation section still exists" \
    "## External Data Validation"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
