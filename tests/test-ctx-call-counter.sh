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
echo "=== Test 5: Statusline displays CTX:N (ex:X bex:Y sr:Z) with global heredoc ==="
# ===================================================================

TMPDIR_T5="$TMPDIR_ROOT/t5"
FAKE_HOME_T5="$TMPDIR_T5/home"
REPO_T5="$TMPDIR_T5/repo"
mkdir -p "$FAKE_HOME_T5/.cache/codebase-memory-mcp" "$REPO_T5"
git -C "$REPO_T5" init -q
REPO_T5_REAL="$(cd "$REPO_T5" && pwd -P)"
HASH_T5=$(echo "$REPO_T5_REAL" | md5 -q 2>/dev/null || echo "$REPO_T5_REAL" | md5sum | awk '{print $1}')

# Pre-populate CTX call counts
python3 -c "
import json
data = {'total_calls': 15, 'by_tool': {
    'mcp__context-mode__ctx_execute': 7,
    'mcp__context-mode__ctx_batch_execute': 5,
    'mcp__context-mode__ctx_search': 3
}}
with open('$FAKE_HOME_T5/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_T5}.json', 'w') as f:
    json.dump(data, f)
"

# Pre-populate CMM call counts (needed by statusline for CMM section)
python3 -c "
import json
data = {'total_calls': 10, 'by_tool': {
    'mcp__codebase-memory-mcp__search_graph': 5,
    'mcp__codebase-memory-mcp__get_code_snippet': 3,
    'mcp__codebase-memory-mcp__trace_path': 2
}}
with open('$FAKE_HOME_T5/.cache/codebase-memory-mcp/_call-counts-${HASH_T5}.json', 'w') as f:
    json.dump(data, f)
"

# Extract the global statusline heredoc from setup.sh
STATUSLINE_TMP="$TMPDIR_T5/statusline-test.sh"
sed -n "/cat > \"\$script_path\" <<'STATUSLINE_SCRIPT'/,/^STATUSLINE_SCRIPT$/p" "$SETUP_SH" \
  | tail -n +2 | sed '$d' > "$STATUSLINE_TMP"
chmod +x "$STATUSLINE_TMP"

OUTPUT=$(cd "$REPO_T5" && HOME="$FAKE_HOME_T5" bash "$STATUSLINE_TMP" 2>/dev/null) || OUTPUT=""

if echo "$OUTPUT" | grep -q 'CTX:15'; then
  pass "Statusline contains CTX:15"
else
  fail "Statusline missing CTX:15 (got: '$OUTPUT')"
fi

if echo "$OUTPUT" | grep -q '(ex:7 bex:5 sr:3)'; then
  pass "Statusline contains CTX details (ex:7 bex:5 sr:3)"
else
  fail "Statusline missing CTX details (got: '$OUTPUT')"
fi

# ===================================================================
echo ""
echo "=== Test 6: Statusline suppresses CTX: when no ctx-call-counts file ==="
# ===================================================================

TMPDIR_T6="$TMPDIR_ROOT/t6"
FAKE_HOME_T6="$TMPDIR_T6/home"
REPO_T6="$TMPDIR_T6/repo"
mkdir -p "$FAKE_HOME_T6/.cache/codebase-memory-mcp" "$REPO_T6"
git -C "$REPO_T6" init -q
REPO_T6_REAL="$(cd "$REPO_T6" && pwd -P)"
HASH_T6=$(echo "$REPO_T6_REAL" | md5 -q 2>/dev/null || echo "$REPO_T6_REAL" | md5sum | awk '{print $1}')

# Only write CMM counts, no CTX counts
python3 -c "
import json
data = {'total_calls': 5, 'by_tool': {}}
with open('$FAKE_HOME_T6/.cache/codebase-memory-mcp/_call-counts-${HASH_T6}.json', 'w') as f:
    json.dump(data, f)
"

STATUSLINE_TMP6="$TMPDIR_T6/statusline-test.sh"
sed -n "/cat > \"\$script_path\" <<'STATUSLINE_SCRIPT'/,/^STATUSLINE_SCRIPT$/p" "$SETUP_SH" \
  | tail -n +2 | sed '$d' > "$STATUSLINE_TMP6"
chmod +x "$STATUSLINE_TMP6"

OUTPUT6=$(cd "$REPO_T6" && HOME="$FAKE_HOME_T6" bash "$STATUSLINE_TMP6" 2>/dev/null) || OUTPUT6=""

if echo "$OUTPUT6" | grep -q 'CTX:'; then
  fail "Statusline shows CTX: when no ctx-call-counts file (got: '$OUTPUT6')"
else
  pass "Statusline correctly suppresses CTX: when no ctx-call-counts file"
fi

# ===================================================================
echo ""
echo "=== Test 7: Wrapper heredoc also displays CTX segment ==="
# ===================================================================

TMPDIR_T7="$TMPDIR_ROOT/t7"
FAKE_HOME_T7="$TMPDIR_T7/home"
REPO_T7="$TMPDIR_T7/repo"
mkdir -p "$FAKE_HOME_T7/.cache/codebase-memory-mcp" "$REPO_T7"
git -C "$REPO_T7" init -q
REPO_T7_REAL="$(cd "$REPO_T7" && pwd -P)"
HASH_T7=$(echo "$REPO_T7_REAL" | md5 -q 2>/dev/null || echo "$REPO_T7_REAL" | md5sum | awk '{print $1}')

# Pre-populate CTX and CMM counts
python3 -c "
import json
ctx = {'total_calls': 8, 'by_tool': {
    'mcp__context-mode__ctx_execute': 4,
    'mcp__context-mode__ctx_batch_execute': 2,
    'mcp__context-mode__ctx_search': 2
}}
with open('$FAKE_HOME_T7/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_T7}.json', 'w') as f:
    json.dump(ctx, f)

cmm = {'total_calls': 6, 'by_tool': {
    'mcp__codebase-memory-mcp__search_graph': 3,
    'mcp__codebase-memory-mcp__get_code_snippet': 2,
    'mcp__codebase-memory-mcp__trace_path': 1
}}
with open('$FAKE_HOME_T7/.cache/codebase-memory-mcp/_call-counts-${HASH_T7}.json', 'w') as f:
    json.dump(cmm, f)
"

# Extract wrapper heredoc from setup.sh
WRAPPER_TMP="$TMPDIR_T7/wrapper-test.sh"
sed -n "/cat > \"\$script_path\" <<'WRAPPER_SCRIPT'/,/^WRAPPER_SCRIPT$/p" "$SETUP_SH" \
  | tail -n +2 | sed '$d' > "$WRAPPER_TMP"
chmod +x "$WRAPPER_TMP"

OUTPUT7=$(cd "$REPO_T7" && HOME="$FAKE_HOME_T7" bash "$WRAPPER_TMP" 2>/dev/null) || OUTPUT7=""

if echo "$OUTPUT7" | grep -q 'CTX:8'; then
  pass "Wrapper statusline contains CTX:8"
else
  fail "Wrapper statusline missing CTX:8 (got: '$OUTPUT7')"
fi

if echo "$OUTPUT7" | grep -q '(ex:4 bex:2 sr:2)'; then
  pass "Wrapper statusline contains CTX details (ex:4 bex:2 sr:2)"
else
  fail "Wrapper statusline missing CTX details (got: '$OUTPUT7')"
fi

# ===================================================================
echo ""
echo "=== Test 8: Config ctx_total=false suppresses CTX segment ==="
# ===================================================================

TMPDIR_T8="$TMPDIR_ROOT/t8"
FAKE_HOME_T8="$TMPDIR_T8/home"
REPO_T8="$TMPDIR_T8/repo"
mkdir -p "$FAKE_HOME_T8/.cache/codebase-memory-mcp" "$REPO_T8"
git -C "$REPO_T8" init -q
REPO_T8_REAL="$(cd "$REPO_T8" && pwd -P)"
HASH_T8=$(echo "$REPO_T8_REAL" | md5 -q 2>/dev/null || echo "$REPO_T8_REAL" | md5sum | awk '{print $1}')

# Pre-populate CTX and CMM counts
python3 -c "
import json
ctx = {'total_calls': 10, 'by_tool': {
    'mcp__context-mode__ctx_execute': 5,
    'mcp__context-mode__ctx_batch_execute': 3,
    'mcp__context-mode__ctx_search': 2
}}
with open('$FAKE_HOME_T8/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_T8}.json', 'w') as f:
    json.dump(ctx, f)

cmm = {'total_calls': 5, 'by_tool': {}}
with open('$FAKE_HOME_T8/.cache/codebase-memory-mcp/_call-counts-${HASH_T8}.json', 'w') as f:
    json.dump(cmm, f)
"

# Write config with ctx_total: false
cat > "$FAKE_HOME_T8/.cache/codebase-memory-mcp/_statusline-config-${HASH_T8}.json" <<'CFGEOF'
{"cmm_total": true, "cmm_details": true, "blocks_total": true, "block_details": true, "ctx_total": false, "ctx_details": true}
CFGEOF

STATUSLINE_TMP8="$TMPDIR_T8/statusline-test.sh"
sed -n "/cat > \"\$script_path\" <<'STATUSLINE_SCRIPT'/,/^STATUSLINE_SCRIPT$/p" "$SETUP_SH" \
  | tail -n +2 | sed '$d' > "$STATUSLINE_TMP8"
chmod +x "$STATUSLINE_TMP8"

OUTPUT8=$(cd "$REPO_T8" && HOME="$FAKE_HOME_T8" bash "$STATUSLINE_TMP8" 2>/dev/null) || OUTPUT8=""

# With ctx_total: false, CTX segment should be absent
if echo "$OUTPUT8" | grep -q 'CTX:'; then
  fail "CTX segment should be suppressed when ctx_total=false (got: '$OUTPUT8')"
else
  pass "CTX segment correctly suppressed when ctx_total=false"
fi

# ===================================================================
echo ""
echo "=== Test 9: Config cmm_details=false suppresses CMM details ==="
# ===================================================================

TMPDIR_T9="$TMPDIR_ROOT/t9"
FAKE_HOME_T9="$TMPDIR_T9/home"
REPO_T9="$TMPDIR_T9/repo"
mkdir -p "$FAKE_HOME_T9/.cache/codebase-memory-mcp" "$REPO_T9"
git -C "$REPO_T9" init -q
REPO_T9_REAL="$(cd "$REPO_T9" && pwd -P)"
HASH_T9=$(echo "$REPO_T9_REAL" | md5 -q 2>/dev/null || echo "$REPO_T9_REAL" | md5sum | awk '{print $1}')

# Pre-populate CMM counts with known values
python3 -c "
import json
cmm = {'total_calls': 20, 'by_tool': {
    'mcp__codebase-memory-mcp__search_graph': 10,
    'mcp__codebase-memory-mcp__get_code_snippet': 7,
    'mcp__codebase-memory-mcp__trace_path': 3
}}
with open('$FAKE_HOME_T9/.cache/codebase-memory-mcp/_call-counts-${HASH_T9}.json', 'w') as f:
    json.dump(cmm, f)
"

# Write config with cmm_details: false
cat > "$FAKE_HOME_T9/.cache/codebase-memory-mcp/_statusline-config-${HASH_T9}.json" <<'CFGEOF'
{"cmm_total": true, "cmm_details": false, "blocks_total": true, "block_details": true, "ctx_total": true, "ctx_details": true}
CFGEOF

STATUSLINE_TMP9="$TMPDIR_T9/statusline-test.sh"
sed -n "/cat > \"\$script_path\" <<'STATUSLINE_SCRIPT'/,/^STATUSLINE_SCRIPT$/p" "$SETUP_SH" \
  | tail -n +2 | sed '$d' > "$STATUSLINE_TMP9"
chmod +x "$STATUSLINE_TMP9"

OUTPUT9=$(cd "$REPO_T9" && HOME="$FAKE_HOME_T9" bash "$STATUSLINE_TMP9" 2>/dev/null) || OUTPUT9=""

if echo "$OUTPUT9" | grep -q 'CMM:20'; then
  pass "CMM total shows (CMM:20)"
else
  fail "CMM total missing (got: '$OUTPUT9')"
fi

# With cmm_details: false, the (sg:X cs:Y tr:Z) breakdown should be absent
if echo "$OUTPUT9" | grep -q '(sg:'; then
  fail "CMM details should be suppressed when cmm_details=false (got: '$OUTPUT9')"
else
  pass "CMM details correctly suppressed when cmm_details=false"
fi

# ===================================================================
echo ""
echo "=== Test 10: No config file -- defaults show all components ==="
# ===================================================================

TMPDIR_T10="$TMPDIR_ROOT/t10"
FAKE_HOME_T10="$TMPDIR_T10/home"
REPO_T10="$TMPDIR_T10/repo"
mkdir -p "$FAKE_HOME_T10/.cache/codebase-memory-mcp" "$REPO_T10"
git -C "$REPO_T10" init -q
REPO_T10_REAL="$(cd "$REPO_T10" && pwd -P)"
HASH_T10=$(echo "$REPO_T10_REAL" | md5 -q 2>/dev/null || echo "$REPO_T10_REAL" | md5sum | awk '{print $1}')

# Pre-populate CTX and CMM counts, no config file
python3 -c "
import json
ctx = {'total_calls': 12, 'by_tool': {
    'mcp__context-mode__ctx_execute': 6,
    'mcp__context-mode__ctx_batch_execute': 4,
    'mcp__context-mode__ctx_search': 2
}}
with open('$FAKE_HOME_T10/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_T10}.json', 'w') as f:
    json.dump(ctx, f)

cmm = {'total_calls': 30, 'by_tool': {
    'mcp__codebase-memory-mcp__search_graph': 15,
    'mcp__codebase-memory-mcp__get_code_snippet': 10,
    'mcp__codebase-memory-mcp__trace_path': 5
}}
with open('$FAKE_HOME_T10/.cache/codebase-memory-mcp/_call-counts-${HASH_T10}.json', 'w') as f:
    json.dump(cmm, f)
"

STATUSLINE_TMP10="$TMPDIR_T10/statusline-test.sh"
sed -n "/cat > \"\$script_path\" <<'STATUSLINE_SCRIPT'/,/^STATUSLINE_SCRIPT$/p" "$SETUP_SH" \
  | tail -n +2 | sed '$d' > "$STATUSLINE_TMP10"
chmod +x "$STATUSLINE_TMP10"

OUTPUT10=$(cd "$REPO_T10" && HOME="$FAKE_HOME_T10" bash "$STATUSLINE_TMP10" 2>/dev/null) || OUTPUT10=""

if echo "$OUTPUT10" | grep -q 'CMM:30'; then
  pass "Default: CMM total present (CMM:30)"
else
  fail "Default: CMM total missing (got: '$OUTPUT10')"
fi

if echo "$OUTPUT10" | grep -q '(sg:15 cs:10 tr:5)'; then
  pass "Default: CMM details present"
else
  fail "Default: CMM details missing (got: '$OUTPUT10')"
fi

if echo "$OUTPUT10" | grep -q 'CTX:12'; then
  pass "Default: CTX total present (CTX:12)"
else
  fail "Default: CTX total missing (got: '$OUTPUT10')"
fi

if echo "$OUTPUT10" | grep -q '(ex:6 bex:4 sr:2)'; then
  pass "Default: CTX details present"
else
  fail "Default: CTX details missing (got: '$OUTPUT10')"
fi

# ===================================================================
echo ""
echo "=== Test 11: Empty stdin -- hook exits 0, no crash ==="
# ===================================================================

TMPDIR_T11="$TMPDIR_ROOT/t11"
FAKE_HOME_T11="$TMPDIR_T11/home"
REPO_T11="$TMPDIR_T11/repo"
mkdir -p "$FAKE_HOME_T11/.cache/codebase-memory-mcp" "$REPO_T11"
git -C "$REPO_T11" init -q

EXIT_T11=0
echo "" | (cd "$REPO_T11" && HOME="$FAKE_HOME_T11" bash "$TRACK_HOOK") 2>/dev/null || EXIT_T11=$?

if [ "$EXIT_T11" -eq 0 ]; then
  pass "Hook exits 0 with empty stdin"
else
  fail "Hook exited $EXIT_T11 with empty stdin (expected 0)"
fi

# ===================================================================
echo ""
echo "=== Test 12: Invalid JSON in cache -- hook recovers gracefully ==="
# ===================================================================

TMPDIR_T12="$TMPDIR_ROOT/t12"
FAKE_HOME_T12="$TMPDIR_T12/home"
REPO_T12="$TMPDIR_T12/repo"
mkdir -p "$FAKE_HOME_T12/.cache/codebase-memory-mcp" "$REPO_T12"
git -C "$REPO_T12" init -q
REPO_T12_REAL="$(cd "$REPO_T12" && pwd -P)"
HASH_T12=$(echo "$REPO_T12_REAL" | md5 -q 2>/dev/null || echo "$REPO_T12_REAL" | md5sum | awk '{print $1}')
COUNTER_T12="$FAKE_HOME_T12/.cache/codebase-memory-mcp/_ctx-call-counts-${HASH_T12}.json"

# Write invalid JSON to the cache file
echo "NOT VALID JSON {{{{" > "$COUNTER_T12"

EXIT_T12=0
echo '{"tool_name": "mcp__context-mode__ctx_execute"}' \
  | (cd "$REPO_T12" && HOME="$FAKE_HOME_T12" bash "$TRACK_HOOK") 2>/dev/null || EXIT_T12=$?

if [ "$EXIT_T12" -eq 0 ]; then
  pass "Hook exits 0 with invalid JSON in cache"
else
  fail "Hook exited $EXIT_T12 with invalid JSON (expected 0)"
fi

# Verify the file was recovered with valid JSON
if [ -f "$COUNTER_T12" ]; then
  RECOVERED=$(python3 -c "import json; d=json.load(open('$COUNTER_T12')); print(d.get('total_calls', 'MISSING'))" 2>/dev/null || echo "ERR")
  if [ "$RECOVERED" = "1" ]; then
    pass "Cache recovered from invalid JSON (total_calls=1)"
  else
    fail "Cache not properly recovered (total_calls=$RECOVERED)"
  fi
fi

# ===================================================================
echo ""
echo "=== Test 13: Read-only cache directory -- hook exits 0 (never blocks) ==="
# ===================================================================

TMPDIR_T13="$TMPDIR_ROOT/t13"
FAKE_HOME_T13="$TMPDIR_T13/home"
REPO_T13="$TMPDIR_T13/repo"
mkdir -p "$FAKE_HOME_T13/.cache/codebase-memory-mcp" "$REPO_T13"
git -C "$REPO_T13" init -q
chmod -w "$FAKE_HOME_T13/.cache/codebase-memory-mcp"

EXIT_T13=0
echo '{"tool_name": "mcp__context-mode__ctx_execute"}' \
  | (cd "$REPO_T13" && HOME="$FAKE_HOME_T13" bash "$TRACK_HOOK") 2>/dev/null || EXIT_T13=$?

# Restore write permissions for cleanup
chmod +w "$FAKE_HOME_T13/.cache/codebase-memory-mcp" 2>/dev/null || true

if [ "$EXIT_T13" -eq 0 ]; then
  pass "Hook exits 0 with read-only cache directory"
else
  fail "Hook exited $EXIT_T13 with read-only cache dir (expected 0)"
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
