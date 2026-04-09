#!/bin/bash
# test-event-logger-fastpath.sh — Tests for context-mode-event-logger.sh fast-path exits
# Verifies CMM/CTX tools exit 0 before sqlite3 pipeline, Write tools hit the full pipeline,
# and the logger exits 0 when Context Mode is not installed.
# Usage: bash tests/test-event-logger-fastpath.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
HOOK="$REPO_ROOT/hooks/project/context-mode-event-logger.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Global fixture setup ---
TMPDIR_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_ROOT"; }
trap cleanup EXIT

# Helper: create a fake git repo with Context Mode detected via .claude/context-mode.db
setup_ctx_repo() {
  local dir="$1"
  mkdir -p "$dir/.claude"
  git -C "$dir" init -q
  touch "$dir/.claude/context-mode.db"
}

# Helper: create a wrapper that detects sqlite3 invocations
# Replaces sqlite3 with a stub that logs calls to a marker file
make_sqlite3_spy() {
  local bindir="$1"
  local marker="$2"
  mkdir -p "$bindir"
  cat > "$bindir/sqlite3" <<'STUB'
#!/bin/bash
echo "sqlite3-called" >> "$SQLITE3_SPY_MARKER"
STUB
  chmod +x "$bindir/sqlite3"
}

# ===================================================================
echo "=== Test 1: CMM tool fast-path exits 0, no sqlite3 calls ==="
# ===================================================================

TMPDIR_T1="$TMPDIR_ROOT/t1"
REPO_T1="$TMPDIR_T1/repo"
FAKE_HOME_T1="$TMPDIR_T1/home"
BINDIR_T1="$TMPDIR_T1/bin"
MARKER_T1="$TMPDIR_T1/sqlite3-spy.log"
setup_ctx_repo "$REPO_T1"
mkdir -p "$FAKE_HOME_T1"
make_sqlite3_spy "$BINDIR_T1" "$MARKER_T1"

EXIT_CODE=0
echo '{"tool_name": "mcp__codebase-memory-mcp__search_graph", "tool_input": {}, "tool_result": "ok"}' \
  | (cd "$REPO_T1" && HOME="$FAKE_HOME_T1" PATH="$BINDIR_T1:$PATH" SQLITE3_SPY_MARKER="$MARKER_T1" bash "$HOOK") 2>/dev/null \
  || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  pass "CMM search_graph exits 0"
else
  fail "CMM search_graph expected exit 0, got $EXIT_CODE"
fi

if [ ! -f "$MARKER_T1" ]; then
  pass "CMM search_graph did not invoke sqlite3 (fast-path)"
else
  fail "CMM search_graph invoked sqlite3 — fast-path did not work"
fi

# ===================================================================
echo ""
echo "=== Test 2: CTX tool fast-path exits 0, no sqlite3 calls ==="
# ===================================================================

TMPDIR_T2="$TMPDIR_ROOT/t2"
REPO_T2="$TMPDIR_T2/repo"
FAKE_HOME_T2="$TMPDIR_T2/home"
BINDIR_T2="$TMPDIR_T2/bin"
MARKER_T2="$TMPDIR_T2/sqlite3-spy.log"
setup_ctx_repo "$REPO_T2"
mkdir -p "$FAKE_HOME_T2"
make_sqlite3_spy "$BINDIR_T2" "$MARKER_T2"

EXIT_CODE=0
echo '{"tool_name": "mcp__context-mode__ctx_execute", "tool_input": {"command": "ls"}, "tool_result": "file1.txt"}' \
  | (cd "$REPO_T2" && HOME="$FAKE_HOME_T2" PATH="$BINDIR_T2:$PATH" SQLITE3_SPY_MARKER="$MARKER_T2" bash "$HOOK") 2>/dev/null \
  || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  pass "CTX ctx_execute exits 0"
else
  fail "CTX ctx_execute expected exit 0, got $EXIT_CODE"
fi

if [ ! -f "$MARKER_T2" ]; then
  pass "CTX ctx_execute did not invoke sqlite3 (fast-path)"
else
  fail "CTX ctx_execute invoked sqlite3 — fast-path did not work"
fi

# ===================================================================
echo ""
echo "=== Test 3: Write tool goes through full pipeline (not fast-path) ==="
# ===================================================================

TMPDIR_T3="$TMPDIR_ROOT/t3"
REPO_T3="$TMPDIR_T3/repo"
FAKE_HOME_T3="$TMPDIR_T3/home"
BINDIR_T3="$TMPDIR_T3/bin"
MARKER_T3="$TMPDIR_T3/sqlite3-spy.log"
setup_ctx_repo "$REPO_T3"
mkdir -p "$FAKE_HOME_T3"
make_sqlite3_spy "$BINDIR_T3" "$MARKER_T3"

EXIT_CODE=0
echo '{"tool_name": "Write", "tool_input": {"file_path": "/tmp/test.txt", "content": "hello"}, "tool_result": "ok"}' \
  | (cd "$REPO_T3" && HOME="$FAKE_HOME_T3" PATH="$BINDIR_T3:$PATH" SQLITE3_SPY_MARKER="$MARKER_T3" bash "$HOOK") 2>/dev/null \
  || EXIT_CODE=$?

# The hook should exit 0 (never blocks) but SHOULD have attempted sqlite3
if [ "$EXIT_CODE" -eq 0 ]; then
  pass "Write tool exits 0"
else
  fail "Write tool expected exit 0, got $EXIT_CODE"
fi

if [ -f "$MARKER_T3" ]; then
  pass "Write tool invoked sqlite3 (went through full pipeline)"
else
  fail "Write tool did not invoke sqlite3 — incorrectly hit fast-path"
fi

# ===================================================================
echo ""
echo "=== Test 4: Read tool without Context Mode installed exits 0 ==="
# ===================================================================

TMPDIR_T4="$TMPDIR_ROOT/t4"
REPO_T4="$TMPDIR_T4/repo"
FAKE_HOME_T4="$TMPDIR_T4/home"
BINDIR_T4="$TMPDIR_T4/bin"
MARKER_T4="$TMPDIR_T4/sqlite3-spy.log"
# Set up a git repo WITHOUT Context Mode (no .claude/context-mode.db, no .mcp.json)
mkdir -p "$REPO_T4" "$FAKE_HOME_T4"
git -C "$REPO_T4" init -q
make_sqlite3_spy "$BINDIR_T4" "$MARKER_T4"

EXIT_CODE=0
echo '{"tool_name": "Read", "tool_input": {"file_path": "/tmp/test.txt"}, "tool_result": "hello"}' \
  | (cd "$REPO_T4" && HOME="$FAKE_HOME_T4" PATH="$BINDIR_T4:$PATH" SQLITE3_SPY_MARKER="$MARKER_T4" bash "$HOOK") 2>/dev/null \
  || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  pass "Read tool exits 0 when CTX not installed"
else
  fail "Read tool expected exit 0 when CTX not installed, got $EXIT_CODE"
fi

if [ ! -f "$MARKER_T4" ]; then
  pass "Read tool did not invoke sqlite3 (CTX not installed early-exit)"
else
  fail "Read tool invoked sqlite3 despite CTX not being installed"
fi

# ===================================================================
echo ""
echo "=== Test 5: Additional CMM tool (index_repository) uses fast-path ==="
# ===================================================================

TMPDIR_T5="$TMPDIR_ROOT/t5"
REPO_T5="$TMPDIR_T5/repo"
FAKE_HOME_T5="$TMPDIR_T5/home"
BINDIR_T5="$TMPDIR_T5/bin"
MARKER_T5="$TMPDIR_T5/sqlite3-spy.log"
setup_ctx_repo "$REPO_T5"
mkdir -p "$FAKE_HOME_T5"
make_sqlite3_spy "$BINDIR_T5" "$MARKER_T5"

EXIT_CODE=0
echo '{"tool_name": "mcp__codebase-memory-mcp__index_repository", "tool_input": {"repo_path": "/tmp"}, "tool_result": "indexed"}' \
  | (cd "$REPO_T5" && HOME="$FAKE_HOME_T5" PATH="$BINDIR_T5:$PATH" SQLITE3_SPY_MARKER="$MARKER_T5" bash "$HOOK") 2>/dev/null \
  || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  pass "CMM index_repository exits 0"
else
  fail "CMM index_repository expected exit 0, got $EXIT_CODE"
fi

if [ ! -f "$MARKER_T5" ]; then
  pass "CMM index_repository did not invoke sqlite3 (fast-path)"
else
  fail "CMM index_repository invoked sqlite3 — fast-path did not work"
fi

# ===================================================================
echo ""
echo "=== Test 6: Edit tool goes through full pipeline (not fast-path) ==="
# ===================================================================

TMPDIR_T6="$TMPDIR_ROOT/t6"
REPO_T6="$TMPDIR_T6/repo"
FAKE_HOME_T6="$TMPDIR_T6/home"
BINDIR_T6="$TMPDIR_T6/bin"
MARKER_T6="$TMPDIR_T6/sqlite3-spy.log"
setup_ctx_repo "$REPO_T6"
mkdir -p "$FAKE_HOME_T6"
make_sqlite3_spy "$BINDIR_T6" "$MARKER_T6"

EXIT_CODE=0
echo '{"tool_name": "Edit", "tool_input": {"file_path": "/tmp/test.txt", "old_string": "a", "new_string": "b"}, "tool_result": "ok"}' \
  | (cd "$REPO_T6" && HOME="$FAKE_HOME_T6" PATH="$BINDIR_T6:$PATH" SQLITE3_SPY_MARKER="$MARKER_T6" bash "$HOOK") 2>/dev/null \
  || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  pass "Edit tool exits 0"
else
  fail "Edit tool expected exit 0, got $EXIT_CODE"
fi

if [ -f "$MARKER_T6" ]; then
  pass "Edit tool invoked sqlite3 (went through full pipeline)"
else
  fail "Edit tool did not invoke sqlite3 — incorrectly hit fast-path"
fi

# ===================================================================
echo ""
echo "--- Results: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
