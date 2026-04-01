#!/bin/bash
# test-hook-block-counter.sh — Tests for hook block counter mechanism
# Usage: bash tests/test-hook-block-counter.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TRACK_HOOK="$REPO_ROOT/hooks/project/track-hook-blocks.sh"
SETUP_SH="$REPO_ROOT/setup.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Global fixture setup ---
TMPDIR_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_ROOT"; }
trap cleanup EXIT

# ===================================================================
echo "=== Test 1: track-hook-blocks.sh increments read_blocks on 'read' argument ==="
# ===================================================================

TMPDIR_T1="$TMPDIR_ROOT/t1"
FAKE_HOME_T1="$TMPDIR_T1/home"
REPO_T1="$TMPDIR_T1/repo"
mkdir -p "$FAKE_HOME_T1/.cache/codebase-memory-mcp" "$REPO_T1"
git -C "$REPO_T1" init -q
REPO_T1_REAL="$(cd "$REPO_T1" && pwd -P)"
HASH_T1=$(echo "$REPO_T1_REAL" | md5 -q 2>/dev/null || echo "$REPO_T1_REAL" | md5sum | awk '{print $1}')
COUNTER_T1="$FAKE_HOME_T1/.cache/codebase-memory-mcp/_block-counts-${HASH_T1}.json"

# Run track-hook-blocks.sh with "read" argument from the temp repo
(cd "$REPO_T1" && HOME="$FAKE_HOME_T1" bash "$TRACK_HOOK" "read") 2>/dev/null

# Verify file exists
if [ -f "$COUNTER_T1" ]; then
  pass "_block-counts-<hash>.json exists after 'read' call"
else
  fail "_block-counts-<hash>.json missing after 'read' call"
fi

# Verify JSON contents
if [ -f "$COUNTER_T1" ]; then
  READ_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T1'))['read_blocks'])" 2>/dev/null || echo "ERR")
  TOTAL_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T1'))['total_blocks'])" 2>/dev/null || echo "ERR")
  BASH_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T1'))['bash_blocks'])" 2>/dev/null || echo "ERR")
  BY_HOOK_CMM=$(python3 -c "import json; print(json.load(open('$COUNTER_T1'))['by_hook']['cmm-nudge'])" 2>/dev/null || echo "ERR")

  if [ "$READ_B" = "1" ]; then pass "read_blocks is 1"; else fail "read_blocks expected 1, got $READ_B"; fi
  if [ "$TOTAL_B" = "1" ]; then pass "total_blocks is 1"; else fail "total_blocks expected 1, got $TOTAL_B"; fi
  if [ "$BASH_B" = "0" ]; then pass "bash_blocks is 0"; else fail "bash_blocks expected 0, got $BASH_B"; fi
  if [ "$BY_HOOK_CMM" = "1" ]; then pass "by_hook.cmm-nudge is 1"; else fail "by_hook.cmm-nudge expected 1, got $BY_HOOK_CMM"; fi
fi

# ===================================================================
echo ""
echo "=== Test 2: track-hook-blocks.sh increments bash_blocks on 'bash' argument ==="
# ===================================================================

TMPDIR_T2="$TMPDIR_ROOT/t2"
FAKE_HOME_T2="$TMPDIR_T2/home"
REPO_T2="$TMPDIR_T2/repo"
mkdir -p "$FAKE_HOME_T2/.cache/codebase-memory-mcp" "$REPO_T2"
git -C "$REPO_T2" init -q
REPO_T2_REAL="$(cd "$REPO_T2" && pwd -P)"
HASH_T2=$(echo "$REPO_T2_REAL" | md5 -q 2>/dev/null || echo "$REPO_T2_REAL" | md5sum | awk '{print $1}')
COUNTER_T2="$FAKE_HOME_T2/.cache/codebase-memory-mcp/_block-counts-${HASH_T2}.json"

# Run track-hook-blocks.sh with "bash" argument
(cd "$REPO_T2" && HOME="$FAKE_HOME_T2" bash "$TRACK_HOOK" "bash") 2>/dev/null

# Verify JSON contents
if [ -f "$COUNTER_T2" ]; then
  BASH_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T2'))['bash_blocks'])" 2>/dev/null || echo "ERR")
  TOTAL_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T2'))['total_blocks'])" 2>/dev/null || echo "ERR")
  READ_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T2'))['read_blocks'])" 2>/dev/null || echo "ERR")
  BY_HOOK_CTX=$(python3 -c "import json; print(json.load(open('$COUNTER_T2'))['by_hook']['ctx-execute-enforcer'])" 2>/dev/null || echo "ERR")

  if [ "$BASH_B" = "1" ]; then pass "bash_blocks is 1"; else fail "bash_blocks expected 1, got $BASH_B"; fi
  if [ "$TOTAL_B" = "1" ]; then pass "total_blocks is 1"; else fail "total_blocks expected 1, got $TOTAL_B"; fi
  if [ "$READ_B" = "0" ]; then pass "read_blocks is 0"; else fail "read_blocks expected 0, got $READ_B"; fi
  if [ "$BY_HOOK_CTX" = "1" ]; then pass "by_hook.ctx-execute-enforcer is 1"; else fail "by_hook.ctx-execute-enforcer expected 1, got $BY_HOOK_CTX"; fi
else
  fail "_block-counts file missing after 'bash' call"
  fail "bash_blocks check skipped"
  fail "total_blocks check skipped"
  fail "read_blocks check skipped"
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
COUNTER_T3="$FAKE_HOME_T3/.cache/codebase-memory-mcp/_block-counts-${HASH_T3}.json"

# Run "read" twice, then "bash" once
(cd "$REPO_T3" && HOME="$FAKE_HOME_T3" bash "$TRACK_HOOK" "read") 2>/dev/null
(cd "$REPO_T3" && HOME="$FAKE_HOME_T3" bash "$TRACK_HOOK" "read") 2>/dev/null
(cd "$REPO_T3" && HOME="$FAKE_HOME_T3" bash "$TRACK_HOOK" "bash") 2>/dev/null

if [ -f "$COUNTER_T3" ]; then
  TOTAL_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T3'))['total_blocks'])" 2>/dev/null || echo "ERR")
  READ_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T3'))['read_blocks'])" 2>/dev/null || echo "ERR")
  BASH_B=$(python3 -c "import json; print(json.load(open('$COUNTER_T3'))['bash_blocks'])" 2>/dev/null || echo "ERR")

  if [ "$TOTAL_B" = "3" ]; then pass "total_blocks accumulated to 3"; else fail "total_blocks expected 3, got $TOTAL_B"; fi
  if [ "$READ_B" = "2" ]; then pass "read_blocks accumulated to 2"; else fail "read_blocks expected 2, got $READ_B"; fi
  if [ "$BASH_B" = "1" ]; then pass "bash_blocks accumulated to 1"; else fail "bash_blocks expected 1, got $BASH_B"; fi
else
  fail "Counter file missing after accumulation test"
fi

# ===================================================================
echo ""
echo "=== Test 4: Project isolation -- different repos get different cache files ==="
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
COUNTER_A="$FAKE_HOME_T4/.cache/codebase-memory-mcp/_block-counts-${HASH_A}.json"
COUNTER_B="$FAKE_HOME_T4/.cache/codebase-memory-mcp/_block-counts-${HASH_B}.json"

# Run "read" from repo A, "bash" from repo B
(cd "$REPO_A" && HOME="$FAKE_HOME_T4" bash "$TRACK_HOOK" "read") 2>/dev/null
(cd "$REPO_B" && HOME="$FAKE_HOME_T4" bash "$TRACK_HOOK" "bash") 2>/dev/null

# Verify distinct hashes
if [ "$HASH_A" != "$HASH_B" ]; then
  pass "Repo A and B have distinct hashes"
else
  fail "Repo A and B produced same hash (collision)"
fi

# Verify repo A has read_blocks=1, bash_blocks=0
if [ -f "$COUNTER_A" ]; then
  RA_READ=$(python3 -c "import json; print(json.load(open('$COUNTER_A'))['read_blocks'])" 2>/dev/null || echo "ERR")
  RA_BASH=$(python3 -c "import json; print(json.load(open('$COUNTER_A'))['bash_blocks'])" 2>/dev/null || echo "ERR")
  if [ "$RA_READ" = "1" ] && [ "$RA_BASH" = "0" ]; then
    pass "Repo A: read_blocks=1, bash_blocks=0 (isolated)"
  else
    fail "Repo A: expected read=1/bash=0, got read=$RA_READ/bash=$RA_BASH"
  fi
else
  fail "Repo A counter file missing"
fi

# Verify repo B has read_blocks=0, bash_blocks=1
if [ -f "$COUNTER_B" ]; then
  RB_READ=$(python3 -c "import json; print(json.load(open('$COUNTER_B'))['read_blocks'])" 2>/dev/null || echo "ERR")
  RB_BASH=$(python3 -c "import json; print(json.load(open('$COUNTER_B'))['bash_blocks'])" 2>/dev/null || echo "ERR")
  if [ "$RB_READ" = "0" ] && [ "$RB_BASH" = "1" ]; then
    pass "Repo B: read_blocks=0, bash_blocks=1 (isolated)"
  else
    fail "Repo B: expected read=0/bash=1, got read=$RB_READ/bash=$RB_BASH"
  fi
else
  fail "Repo B counter file missing"
fi

# ===================================================================
echo ""
echo "=== Test 5: Statusline displays Blk: when block counts exist ==="
# ===================================================================
# The installed .claude/hooks/statusline-cmm.sh may not have block count support.
# Extract the global statusline heredoc from setup.sh and test that directly.

TMPDIR_T5="$TMPDIR_ROOT/t5"
FAKE_HOME_T5="$TMPDIR_T5/home"
REPO_T5="$TMPDIR_T5/repo"
mkdir -p "$FAKE_HOME_T5/.cache/codebase-memory-mcp" "$REPO_T5"
git -C "$REPO_T5" init -q
REPO_T5_REAL="$(cd "$REPO_T5" && pwd -P)"
HASH_T5=$(echo "$REPO_T5_REAL" | md5 -q 2>/dev/null || echo "$REPO_T5_REAL" | md5sum | awk '{print $1}')

# Write known block-counts JSON
python3 -c "
import json
data = {'total_blocks': 20, 'read_blocks': 12, 'bash_blocks': 8, 'by_hook': {'cmm-nudge': 12, 'ctx-execute-enforcer': 8}}
with open('$FAKE_HOME_T5/.cache/codebase-memory-mcp/_block-counts-${HASH_T5}.json', 'w') as f:
    json.dump(data, f)
"

# Write minimal call-counts JSON so CMM stats section works
python3 -c "
import json
data = {'total_calls': 47, 'by_tool': {'mcp__codebase-memory-mcp__search_graph': 20, 'mcp__codebase-memory-mcp__get_code_snippet': 15, 'mcp__codebase-memory-mcp__trace_call_path': 12}}
with open('$FAKE_HOME_T5/.cache/codebase-memory-mcp/_call-counts-${HASH_T5}.json', 'w') as f:
    json.dump(data, f)
"

# Extract the global statusline heredoc from setup.sh to a temp script
# (This is the source of truth -- the installed copy may lag)
STATUSLINE_TMP="$TMPDIR_T5/statusline-test.sh"
sed -n "/cat > \"\$script_path\" <<'STATUSLINE_SCRIPT'/,/^STATUSLINE_SCRIPT$/p" "$SETUP_SH" \
  | tail -n +2 | sed '$d' > "$STATUSLINE_TMP"
chmod +x "$STATUSLINE_TMP"

# Run the extracted statusline from the test repo
OUTPUT=$(cd "$REPO_T5" && HOME="$FAKE_HOME_T5" bash "$STATUSLINE_TMP" 2>/dev/null) || OUTPUT=""

if echo "$OUTPUT" | grep -q 'Blk:R12/B8'; then
  pass "Statusline output contains 'Blk:R12/B8'"
else
  fail "Statusline output missing 'Blk:R12/B8' (got: '$OUTPUT')"
fi

if echo "$OUTPUT" | grep -q 'CMM:47'; then
  pass "Statusline output contains 'CMM:47'"
else
  fail "Statusline output missing 'CMM:47' (got: '$OUTPUT')"
fi

# ===================================================================
echo ""
echo "=== Test 6: Statusline suppresses Blk: when counts are zero ==="
# ===================================================================

TMPDIR_T6="$TMPDIR_ROOT/t6"
FAKE_HOME_T6="$TMPDIR_T6/home"
REPO_T6="$TMPDIR_T6/repo"
mkdir -p "$FAKE_HOME_T6/.cache/codebase-memory-mcp" "$REPO_T6"
git -C "$REPO_T6" init -q
REPO_T6_REAL="$(cd "$REPO_T6" && pwd -P)"
HASH_T6=$(echo "$REPO_T6_REAL" | md5 -q 2>/dev/null || echo "$REPO_T6_REAL" | md5sum | awk '{print $1}')

# Write block-counts JSON with all zeros
python3 -c "
import json
data = {'total_blocks': 0, 'read_blocks': 0, 'bash_blocks': 0, 'by_hook': {}}
with open('$FAKE_HOME_T6/.cache/codebase-memory-mcp/_block-counts-${HASH_T6}.json', 'w') as f:
    json.dump(data, f)
"

# Write minimal call-counts JSON
python3 -c "
import json
data = {'total_calls': 5, 'by_tool': {}}
with open('$FAKE_HOME_T6/.cache/codebase-memory-mcp/_call-counts-${HASH_T6}.json', 'w') as f:
    json.dump(data, f)
"

# Use the same extracted global statusline heredoc
STATUSLINE_TMP6="$TMPDIR_T6/statusline-test.sh"
sed -n "/cat > \"\$script_path\" <<'STATUSLINE_SCRIPT'/,/^STATUSLINE_SCRIPT$/p" "$SETUP_SH" \
  | tail -n +2 | sed '$d' > "$STATUSLINE_TMP6"
chmod +x "$STATUSLINE_TMP6"

OUTPUT6=$(cd "$REPO_T6" && HOME="$FAKE_HOME_T6" bash "$STATUSLINE_TMP6" 2>/dev/null) || OUTPUT6=""

if echo "$OUTPUT6" | grep -q 'Blk:'; then
  fail "Statusline shows 'Blk:' when counts are zero (got: '$OUTPUT6')"
else
  pass "Statusline correctly suppresses 'Blk:' when counts are zero"
fi

# ===================================================================
echo ""
echo "=== Test 7: track-hook-blocks.sh always exits 0 (error resilience) ==="
# ===================================================================

TMPDIR_T7="$TMPDIR_ROOT/t7"
FAKE_HOME_T7="$TMPDIR_T7/home"
REPO_T7="$TMPDIR_T7/repo"
mkdir -p "$FAKE_HOME_T7/.cache/codebase-memory-mcp" "$REPO_T7"
git -C "$REPO_T7" init -q

# Sub-test 7a: No arguments (unknown hook type)
EXIT_7A=0
(cd "$REPO_T7" && HOME="$FAKE_HOME_T7" bash "$TRACK_HOOK") 2>/dev/null || EXIT_7A=$?
if [ "$EXIT_7A" -eq 0 ]; then
  pass "exits 0 with no arguments"
else
  fail "exited $EXIT_7A with no arguments (expected 0)"
fi

# Sub-test 7b: Invalid JSON in existing cache file
REPO_T7B_REAL="$(cd "$REPO_T7" && pwd -P)"
HASH_T7=$(echo "$REPO_T7B_REAL" | md5 -q 2>/dev/null || echo "$REPO_T7B_REAL" | md5sum | awk '{print $1}')
COUNTER_T7="$FAKE_HOME_T7/.cache/codebase-memory-mcp/_block-counts-${HASH_T7}.json"
echo "NOT VALID JSON {{{{" > "$COUNTER_T7"

EXIT_7B=0
(cd "$REPO_T7" && HOME="$FAKE_HOME_T7" bash "$TRACK_HOOK" "read") 2>/dev/null || EXIT_7B=$?
if [ "$EXIT_7B" -eq 0 ]; then
  pass "exits 0 with invalid JSON in cache"
else
  fail "exited $EXIT_7B with invalid JSON (expected 0)"
fi

# Verify the file was recovered (should now have valid JSON with read_blocks=1)
if [ -f "$COUNTER_T7" ]; then
  RECOVERED=$(python3 -c "import json; d=json.load(open('$COUNTER_T7')); print(d.get('read_blocks', 'MISSING'))" 2>/dev/null || echo "ERR")
  if [ "$RECOVERED" = "1" ]; then
    pass "cache recovered from invalid JSON (read_blocks=1)"
  else
    fail "cache not properly recovered (read_blocks=$RECOVERED)"
  fi
fi

# Sub-test 7c: Read-only cache directory
TMPDIR_T7C="$TMPDIR_ROOT/t7c"
FAKE_HOME_T7C="$TMPDIR_T7C/home"
REPO_T7C="$TMPDIR_T7C/repo"
mkdir -p "$FAKE_HOME_T7C/.cache/codebase-memory-mcp" "$REPO_T7C"
git -C "$REPO_T7C" init -q
chmod -w "$FAKE_HOME_T7C/.cache/codebase-memory-mcp"

EXIT_7C=0
(cd "$REPO_T7C" && HOME="$FAKE_HOME_T7C" bash "$TRACK_HOOK" "read") 2>/dev/null || EXIT_7C=$?

# Restore write permissions for cleanup
chmod +w "$FAKE_HOME_T7C/.cache/codebase-memory-mcp" 2>/dev/null || true

if [ "$EXIT_7C" -eq 0 ]; then
  pass "exits 0 with read-only cache directory"
else
  fail "exited $EXIT_7C with read-only cache dir (expected 0)"
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
