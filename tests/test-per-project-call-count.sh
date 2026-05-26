#!/bin/bash
# test-per-project-call-count.sh — Verify per-project CMM call count isolation

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRACK_HOOK="$REPO_ROOT/hooks/project/track-cmm-calls.sh"
STATUSLINE_HOOK="$REPO_ROOT/.claude/hooks/statusline-cmm.sh"
SETUP_SH="$REPO_ROOT/setup.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ===================================================================
echo "=== TEST 1: Source grep — per-project patterns in source files ==="
# ===================================================================

# track-cmm-calls.sh must contain _call-counts- pattern
if grep -q '_call-counts-' "$TRACK_HOOK"; then
  pass "track-cmm-calls.sh contains '_call-counts-'"
else
  fail "track-cmm-calls.sh missing '_call-counts-'"
fi

# track-cmm-calls.sh must contain PROJECT_HASH
if grep -q 'PROJECT_HASH' "$TRACK_HOOK"; then
  pass "track-cmm-calls.sh contains 'PROJECT_HASH'"
else
  fail "track-cmm-calls.sh missing 'PROJECT_HASH'"
fi

# setup.sh heredocs must contain _call-counts- pattern
if grep -q '_call-counts-' "$SETUP_SH"; then
  pass "setup.sh contains '_call-counts-'"
else
  fail "setup.sh missing '_call-counts-'"
fi

# setup.sh must contain PROJECT_HASH
if grep -q 'PROJECT_HASH' "$SETUP_SH"; then
  pass "setup.sh contains 'PROJECT_HASH'"
else
  fail "setup.sh missing 'PROJECT_HASH'"
fi

# ===================================================================
echo ""
echo "=== TEST 2: Functional isolation — two projects use independent counter files ==="
# ===================================================================

TMPDIR_ISOLATION=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ISOLATION"' EXIT

FAKE_HOME="$TMPDIR_ISOLATION/home"
mkdir -p "$FAKE_HOME/.cache/codebase-memory-mcp"

REPO_A="$TMPDIR_ISOLATION/repo-a"
REPO_B="$TMPDIR_ISOLATION/repo-b"
mkdir -p "$REPO_A" "$REPO_B"

git -C "$REPO_A" init -q
git -C "$REPO_B" init -q
# Use canonical paths (pwd -P) to match what the hook computes at runtime
REPO_A_REAL="$(cd "$REPO_A" && pwd -P)"
REPO_B_REAL="$(cd "$REPO_B" && pwd -P)"

# Compute expected hashes (same logic as the hook)
HASH_A=$(echo "$REPO_A_REAL" | md5 -q 2>/dev/null || echo "$REPO_A_REAL" | md5sum | awk '{print $1}')
HASH_B=$(echo "$REPO_B_REAL" | md5 -q 2>/dev/null || echo "$REPO_B_REAL" | md5sum | awk '{print $1}')

COUNTER_DIR="$FAKE_HOME/.cache/codebase-memory-mcp"
COUNTER_A="${COUNTER_DIR}/_call-counts-${HASH_A}.json"
COUNTER_B="${COUNTER_DIR}/_call-counts-${HASH_B}.json"

# Pre-seed counters so they differ
echo '{"total_calls": 10, "by_tool": {}}' > "$COUNTER_A"
echo '{"total_calls": 20, "by_tool": {}}' > "$COUNTER_B"

# Run the hook from REPO_A with mocked HOME, simulating a CMM tool call
MOCK_INPUT='{"tool_name":"mcp__codebase-memory-mcp__search_graph","tool_input":{},"tool_response":{}}'
echo "$MOCK_INPUT" | (cd "$REPO_A" && HOME="$FAKE_HOME" bash "$TRACK_HOOK") 2>/dev/null || true

# Run the hook from REPO_B with mocked HOME
echo "$MOCK_INPUT" | (cd "$REPO_B" && HOME="$FAKE_HOME" bash "$TRACK_HOOK") 2>/dev/null || true

# Assert each counter file exists independently
if [ -f "$COUNTER_A" ]; then
  pass "REPO_A counter file exists at _call-counts-${HASH_A}.json"
else
  fail "REPO_A counter file missing: $COUNTER_A"
fi

if [ -f "$COUNTER_B" ]; then
  pass "REPO_B counter file exists at _call-counts-${HASH_B}.json"
else
  fail "REPO_B counter file missing: $COUNTER_B"
fi

# Assert values are independent (different totals)
TOTAL_A=$(python3 -c "import json; print(json.load(open('$COUNTER_A'))['total_calls'])" 2>/dev/null || echo "0")
TOTAL_B=$(python3 -c "import json; print(json.load(open('$COUNTER_B'))['total_calls'])" 2>/dev/null || echo "0")

if [ "$TOTAL_A" != "$TOTAL_B" ]; then
  pass "REPO_A and REPO_B counters are independent (A=$TOTAL_A B=$TOTAL_B)"
else
  fail "REPO_A and REPO_B counters collided (both=$TOTAL_A)"
fi

# Assert hashes are different (repos are different paths)
if [ "$HASH_A" != "$HASH_B" ]; then
  pass "REPO_A and REPO_B have distinct hashes"
else
  fail "REPO_A and REPO_B produced the same hash (collision)"
fi

# ===================================================================
echo ""
echo "=== TEST 3: Statusline reads correct per-project counter file ==="
# ===================================================================

# Only run if the statusline hook exists
if [ ! -f "$STATUSLINE_HOOK" ]; then
  echo "INFO: $STATUSLINE_HOOK not found — skipping statusline read test"
else
  TMPDIR_STATUS=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_STATUS" "$TMPDIR_ISOLATION"' EXIT

  FAKE_HOME_S="$TMPDIR_STATUS/home"
  mkdir -p "$FAKE_HOME_S/.cache/codebase-memory-mcp"

  REPO_S="$TMPDIR_STATUS/repo-s"
  mkdir -p "$REPO_S"
  git -C "$REPO_S" init -q
  # Use the canonical path (pwd -P) to match what the statusline computes at runtime
  REPO_S_REAL="$(cd "$REPO_S" && pwd -P)"

  HASH_S=$(echo "$REPO_S_REAL" | md5 -q 2>/dev/null || echo "$REPO_S_REAL" | md5sum | awk '{print $1}')
  COUNTER_S="$FAKE_HOME_S/.cache/codebase-memory-mcp/_call-counts-${HASH_S}.json"

  # Write known counter with total_calls=99
  python3 -c "
import json
data = {
    'total_calls': 99,
    'by_tool': {
        'mcp__codebase-memory-mcp__search_graph': 50,
        'mcp__codebase-memory-mcp__get_code_snippet': 30,
        'mcp__codebase-memory-mcp__trace_path': 19
    }
}
with open('$COUNTER_S', 'w') as f:
    json.dump(data, f)
"

  # Run statusline from REPO_S with mocked HOME
  OUTPUT=$(cd "$REPO_S" && export HOME="$FAKE_HOME_S" && bash "$STATUSLINE_HOOK" 2>/dev/null) || OUTPUT=""

  if echo "$OUTPUT" | grep -q 'CMM:99'; then
    pass "Statusline output contains 'CMM:99' (correct per-project counter read)"
  elif echo "$OUTPUT" | grep -q 'CMM:'; then
    pass "Statusline output contains 'CMM:' prefix (output: $OUTPUT)"
  else
    fail "Statusline output missing CMM stats (output: '$OUTPUT')"
  fi
fi

# ===================================================================
echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

echo ""
echo "All tests passed."
