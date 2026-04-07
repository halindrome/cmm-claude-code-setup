#!/bin/bash
# test-ctx-call-counter.sh — Tests for Context Mode call counter hook and statusline display
# Usage: bash tests/test-ctx-call-counter.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TRACK_HOOK="$REPO_ROOT/hooks/project/track-ctx-calls.sh"
SETUP_SH="$REPO_ROOT/setup.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Global fixture setup ---
TMPDIR_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_ROOT"; }
trap cleanup EXIT

# ===================================================================
echo "=== Test 1: Single ctx_execute event increments counters ==="
# ===================================================================

TMPDIR_T1="$TMPDIR_ROOT/t1"
FAKE_HOME_T1="$TMPDIR_T1/home"
REPO_T1="$TMPDIR_T1/repo"
mkdir -p "$FAKE_HOME_T1/.cache/codebase-memory-mcp" "$REPO_T1"
git -C "$REPO_T1" init -q
REPO_T1_REAL="$(cd "$REPO_T1" && pwd -P)"
HASH_T1=$(echo "$REPO_T1_REAL" | md5 -q 2>/dev/null || echo "$REPO_T1_REAL" | md5sum | awk '{print $1}')
COUNTER_T1="$FAKE_HOME_T1/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_T1}.json"

echo '{"tool_name": "mcp__context-mode__ctx_execute"}' \
  | (cd "$REPO_T1" && HOME="$FAKE_HOME_T1" bash "$TRACK_HOOK") 2>/dev/null

if [ -f "$COUNTER_T1" ]; then
  pass "_ctx-call-counts file exists after ctx_execute event"
else
  fail "_ctx-call-counts file missing after ctx_execute event"
fi

if [ -f "$COUNTER_T1" ]; then
  TOTAL=$(python3 -c "import json; print(json.load(open('$COUNTER_T1'))['total_calls'])" 2>/dev/null || echo "ERR")
  BY_TOOL=$(python3 -c "import json; print(json.load(open('$COUNTER_T1'))['by_tool']['mcp__context-mode__ctx_execute'])" 2>/dev/null || echo "ERR")

  if [ "$TOTAL" = "1" ]; then pass "total_calls is 1"; else fail "total_calls expected 1, got $TOTAL"; fi
  if [ "$BY_TOOL" = "1" ]; then pass "by_tool.ctx_execute is 1"; else fail "by_tool.ctx_execute expected 1, got $BY_TOOL"; fi
fi

# ===================================================================
echo ""
echo "=== Test 2: Different ctx tools increment independently ==="
# ===================================================================

TMPDIR_T2="$TMPDIR_ROOT/t2"
FAKE_HOME_T2="$TMPDIR_T2/home"
REPO_T2="$TMPDIR_T2/repo"
mkdir -p "$FAKE_HOME_T2/.cache/codebase-memory-mcp" "$REPO_T2"
git -C "$REPO_T2" init -q
REPO_T2_REAL="$(cd "$REPO_T2" && pwd -P)"
HASH_T2=$(echo "$REPO_T2_REAL" | md5 -q 2>/dev/null || echo "$REPO_T2_REAL" | md5sum | awk '{print $1}')
COUNTER_T2="$FAKE_HOME_T2/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_T2}.json"

echo '{"tool_name": "mcp__context-mode__ctx_batch_execute"}' \
  | (cd "$REPO_T2" && HOME="$FAKE_HOME_T2" bash "$TRACK_HOOK") 2>/dev/null
echo '{"tool_name": "mcp__context-mode__ctx_search"}' \
  | (cd "$REPO_T2" && HOME="$FAKE_HOME_T2" bash "$TRACK_HOOK") 2>/dev/null

if [ -f "$COUNTER_T2" ]; then
  TOTAL=$(python3 -c "import json; print(json.load(open('$COUNTER_T2'))['total_calls'])" 2>/dev/null || echo "ERR")
  BATCH=$(python3 -c "import json; print(json.load(open('$COUNTER_T2'))['by_tool']['mcp__context-mode__ctx_batch_execute'])" 2>/dev/null || echo "ERR")
  SEARCH=$(python3 -c "import json; print(json.load(open('$COUNTER_T2'))['by_tool']['mcp__context-mode__ctx_search'])" 2>/dev/null || echo "ERR")

  if [ "$TOTAL" = "2" ]; then pass "total_calls is 2"; else fail "total_calls expected 2, got $TOTAL"; fi
  if [ "$BATCH" = "1" ]; then pass "by_tool.ctx_batch_execute is 1"; else fail "by_tool.ctx_batch_execute expected 1, got $BATCH"; fi
  if [ "$SEARCH" = "1" ]; then pass "by_tool.ctx_search is 1"; else fail "by_tool.ctx_search expected 1, got $SEARCH"; fi
else
  fail "Counter file missing after two distinct tool events"
fi

# ===================================================================
echo ""
echo "=== Test 3: Counts accumulate across multiple calls ==="
# ===================================================================

TMPDIR_T3="$TMPDIR_ROOT/t3"
FAKE_HOME_T3="$TMPDIR_T3/home"
REPO_T3="$TMPDIR_T3/repo"
mkdir -p "$FAKE_HOME_T3/.cache/codebase-memory-mcp" "$REPO_T3"
git -C "$REPO_T3" init -q
REPO_T3_REAL="$(cd "$REPO_T3" && pwd -P)"
HASH_T3=$(echo "$REPO_T3_REAL" | md5 -q 2>/dev/null || echo "$REPO_T3_REAL" | md5sum | awk '{print $1}')
COUNTER_T3="$FAKE_HOME_T3/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_T3}.json"

echo '{"tool_name": "mcp__context-mode__ctx_execute"}' \
  | (cd "$REPO_T3" && HOME="$FAKE_HOME_T3" bash "$TRACK_HOOK") 2>/dev/null
echo '{"tool_name": "mcp__context-mode__ctx_execute"}' \
  | (cd "$REPO_T3" && HOME="$FAKE_HOME_T3" bash "$TRACK_HOOK") 2>/dev/null
echo '{"tool_name": "mcp__context-mode__ctx_execute"}' \
  | (cd "$REPO_T3" && HOME="$FAKE_HOME_T3" bash "$TRACK_HOOK") 2>/dev/null

if [ -f "$COUNTER_T3" ]; then
  TOTAL=$(python3 -c "import json; print(json.load(open('$COUNTER_T3'))['total_calls'])" 2>/dev/null || echo "ERR")
  BY_TOOL=$(python3 -c "import json; print(json.load(open('$COUNTER_T3'))['by_tool']['mcp__context-mode__ctx_execute'])" 2>/dev/null || echo "ERR")

  if [ "$TOTAL" = "3" ]; then pass "total_calls accumulated to 3"; else fail "total_calls expected 3, got $TOTAL"; fi
  if [ "$BY_TOOL" = "3" ]; then pass "by_tool.ctx_execute accumulated to 3"; else fail "by_tool.ctx_execute expected 3, got $BY_TOOL"; fi
else
  fail "Counter file missing after accumulation test"
fi

# ===================================================================
echo ""
echo "=== Test 4: Project isolation -- different repos get independent counters ==="
# ===================================================================

TMPDIR_T4="$TMPDIR_ROOT/t4"
FAKE_HOME_T4="$TMPDIR_T4/home"
REPO_A="$TMPDIR_T4/repo-a"
REPO_B="$TMPDIR_T4/repo-b"
mkdir -p "$FAKE_HOME_T4/.cache/codebase-memory-mcp" "$REPO_A" "$REPO_B"
git -C "$REPO_A" init -q
git -C "$REPO_B" init -q
REPO_A_REAL="$(cd "$REPO_A" && pwd -P)"
REPO_B_REAL="$(cd "$REPO_B" && pwd -P)"
HASH_A=$(echo "$REPO_A_REAL" | md5 -q 2>/dev/null || echo "$REPO_A_REAL" | md5sum | awk '{print $1}')
HASH_B=$(echo "$REPO_B_REAL" | md5 -q 2>/dev/null || echo "$REPO_B_REAL" | md5sum | awk '{print $1}')
COUNTER_A="$FAKE_HOME_T4/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_A}.json"
COUNTER_B="$FAKE_HOME_T4/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_B}.json"

# Feed 2 events to repo A, 1 event to repo B
echo '{"tool_name": "mcp__context-mode__ctx_execute"}' \
  | (cd "$REPO_A" && HOME="$FAKE_HOME_T4" bash "$TRACK_HOOK") 2>/dev/null
echo '{"tool_name": "mcp__context-mode__ctx_execute"}' \
  | (cd "$REPO_A" && HOME="$FAKE_HOME_T4" bash "$TRACK_HOOK") 2>/dev/null
echo '{"tool_name": "mcp__context-mode__ctx_search"}' \
  | (cd "$REPO_B" && HOME="$FAKE_HOME_T4" bash "$TRACK_HOOK") 2>/dev/null

if [ "$HASH_A" != "$HASH_B" ]; then
  pass "Repo A and B have distinct hashes"
else
  fail "Repo A and B produced same hash (collision)"
fi

if [ -f "$COUNTER_A" ]; then
  TOTAL_A=$(python3 -c "import json; print(json.load(open('$COUNTER_A'))['total_calls'])" 2>/dev/null || echo "ERR")
  if [ "$TOTAL_A" = "2" ]; then
    pass "Repo A: total_calls=2 (isolated)"
  else
    fail "Repo A: expected total_calls=2, got $TOTAL_A"
  fi
else
  fail "Repo A counter file missing"
fi

if [ -f "$COUNTER_B" ]; then
  TOTAL_B=$(python3 -c "import json; print(json.load(open('$COUNTER_B'))['total_calls'])" 2>/dev/null || echo "ERR")
  if [ "$TOTAL_B" = "1" ]; then
    pass "Repo B: total_calls=1 (isolated)"
  else
    fail "Repo B: expected total_calls=1, got $TOTAL_B"
  fi
else
  fail "Repo B counter file missing"
fi

# ===================================================================
echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo ""
echo "All tests passed."
