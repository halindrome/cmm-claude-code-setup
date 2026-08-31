#!/bin/bash
# test-scout-context-mode.sh — Verify the Scout agent DELTA carries the Context Mode
# integration this repo adds on top of upstream VBW.
#
# SCOPE: agents/vbw-scout.md is a DELTA over the upstream VBW agent body (since
# 8abfefe), not a standalone agent definition. Assert only what this repo owns:
# the Context Mode sections and tool references it injects, plus the read-only
# guarantees that must survive an upstream sync. Do NOT assert on upstream base
# content — it is not in this file, and doing so is what left this suite red.
#
# Usage: bash tests/test-scout-context-mode.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCOUT_FILE="$SCRIPT_DIR/../agents/vbw-scout.md"

PASS=0; FAIL=0

_assert_contains() {
    local label="$1" pattern="$2"
    if grep -Eq "$pattern" "$SCOUT_FILE" 2>/dev/null; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (pattern not found: $pattern)"
        FAIL=$((FAIL+1))
    fi
}

_assert_not_contains() {
    local label="$1" pattern="$2"
    if grep -Eq "$pattern" "$SCOUT_FILE" 2>/dev/null; then
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

# --- Positive content tests: fallback ---
echo ""
echo "--- Fallback language ---"

_assert_contains "WebFetch fallback language present" \
    "WebFetch"

_assert_contains "Context Mode Capture section header exists" \
    "## Context Mode Capture"

# --- Structural tests: the file is a DELTA, not a full agent body ---
#
# This block replaces five assertions that encoded the PRE-delta contract and had
# been failing since the file was restructured. Two upstream commits changed it:
#
#   17a3302  align vbw-scout.md with upstream v1.36.2
#            disallowedTools: "Bash, Edit, NotebookEdit, Task"
#                          -> "Edit, NotebookEdit, Task, TaskCreate, Agent, ..."
#            i.e. Scout was deliberately GRANTED Bash. The old
#            `disallowedTools:.*Bash` assertion, and the two negative assertions
#            forbidding ctx_execute/ctx_batch_execute "because they require Bash",
#            all rest on a premise that no longer holds.
#
#   8abfefe  apply delta-only format to vbw-lead, vbw-qa, vbw-scout
#            226 -> 90 lines. "## MCP Tool Usage" and "## External Data
#            Validation" now live in the UPSTREAM BASE, and the extension
#            delimiter comments went away with the merge format. Asserting on
#            base content from the delta is wrong by construction.
#
# So assert what the delta actually owns, and assert the delta SHAPE — which is
# what would really regress if someone re-inlined the full upstream body.
echo ""
echo "--- Delta-only structure ---"

_assert_not_contains "delta does NOT re-inline the upstream MCP Tool Usage section" \
    "^## MCP Tool Usage"

_assert_not_contains "delta does NOT re-inline the upstream External Data Validation section" \
    "^## External Data Validation"

# Scout is a research agent: read-only guarantees must survive any upstream sync.
# Bash is deliberately NOT asserted here — 17a3302 granted it on purpose.
_assert_contains "frontmatter declares disallowedTools" \
    "^disallowedTools:"

# Match Edit as a LIST ITEM, not a substring: "disallowedTools:.*Edit" is
# satisfied by "NotebookEdit", so dropping Edit alone could never fail the test.
_assert_contains "Edit remains disallowed (read-only research agent)" \
    "^disallowedTools:( *|.*, )Edit(,|\$)"

_assert_contains "NotebookEdit remains disallowed" \
    "^disallowedTools:( *|.*, )NotebookEdit(,|\$)"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
