#!/bin/bash
# test-hook-driven-indexing.sh — hooks refresh the CMM index; subagents get guidance, not state
# Covers: cmm-session-start.sh background index launch, agent-cmm-gate.sh spawn hold,
# subagent-cmm-startup.sh guidance text.
# Usage: bash tests/test-hook-driven-indexing.sh
# Exit: 0 = all pass, 1 = any failure
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC="$SCRIPT_DIR/../hooks"

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Fake installed project: <root>/.claude/hooks/{*.sh,lib/*.sh}
FAKE_ROOT=$(mktemp -d /tmp/cmm-test-hdi-XXXXXX)
git -C "$FAKE_ROOT" init -q
git -C "$FAKE_ROOT" commit --allow-empty -q -m "init"
HOOKS="$FAKE_ROOT/.claude/hooks"
mkdir -p "$HOOKS/lib"
cp "$SRC/project/cmm-session-start.sh" "$SRC/project/agent-cmm-gate.sh" "$SRC/project/subagent-cmm-startup.sh" "$HOOKS/"
cp "$SRC/lib/"*.sh "$HOOKS/lib/"

ROOT="$(cd "$FAKE_ROOT" && git rev-parse --show-toplevel)"
HASH=$(echo "$ROOT" | md5 -q 2>/dev/null || echo "$ROOT" | md5sum | awk '{print $1}')
SENTINEL="/tmp/cmm-session-ready-${HASH}"
MARKER="/tmp/cmm-indexing-${HASH}"
PIDFILE="/tmp/cmm-indexer-${HASH}.pid"
CTX_SENTINEL="/tmp/context-mode-ready-${HASH}"
PROJECT="${ROOT#/}"; PROJECT="${PROJECT//\//-}"

# Stub CLI: prints an "indexed" result after a short delay, or fails when STUB_FAIL=1.
STUB_DIR="$FAKE_ROOT/stub"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/codebase-memory-mcp" <<'STUB'
#!/bin/bash
sleep 1
[ "${STUB_FAIL:-0}" = "1" ] && { echo '{"error":"version conflict"}'; exit 1; }
echo '{"project":"x","status":"indexed"}'
STUB
chmod +x "$STUB_DIR/codebase-memory-mcp"

cleanup() { rm -rf "$FAKE_ROOT"; rm -f "$SENTINEL" "$MARKER" "$PIDFILE" "$CTX_SENTINEL"; }
trap cleanup EXIT

_wait_gone() { for _ in $(seq 1 40); do [ -f "$1" ] || return 0; sleep 0.25; done; return 1; }

run_start() { (cd "$FAKE_ROOT" && echo '{}' | env -u CLAUDE_AGENT_ID -u CLAUDE_PARENT_SESSION_ID "$@" bash "$HOOKS/cmm-session-start.sh" >/dev/null 2>&1); }

# --- 1. Session start returns immediately and the background job opens the gate ---
echo "--- 1: session start launches a detached index refresh ---"
rm -f "$SENTINEL" "$PIDFILE"
run_start PATH="$STUB_DIR:$PATH"
[ -f "$PIDFILE" ] && _pass "1a: indexer PID recorded" || _fail "1a: no PID file"
kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null \
  && _pass "1b: hook returned while the indexer was still running (detached)" \
  || _fail "1b: indexer already gone when hook returned (hook waited on it?)"
_wait_gone "$PIDFILE" && _pass "1c: PID file removed when indexer exits" || _fail "1c: PID file left behind"
grep -qx ready "$SENTINEL" 2>/dev/null && _pass "1d: sentinel written as ready" || _fail "1d: sentinel not ready"
[ ! -f "$MARKER" ] && _pass "1e: indexing marker cleared" || _fail "1e: indexing marker still present"

# --- 2. A failed CLI run leaves the gate exactly as before ---
echo "--- 2: failing CLI leaves no sentinel and keeps the fail-open marker ---"
rm -f "$SENTINEL" "$PIDFILE"
run_start PATH="$STUB_DIR:$PATH" STUB_FAIL=1
_wait_gone "$PIDFILE"
[ ! -f "$SENTINEL" ] && _pass "2a: no sentinel on failure" || _fail "2a: sentinel written despite failure"
[ -f "$MARKER" ] && _pass "2b: fail-open marker kept" || _fail "2b: marker removed on failure"

# --- 3. Agent sessions never launch an indexer ---
echo "--- 3: agent session does not launch ---"
rm -f "$PIDFILE"
(cd "$FAKE_ROOT" && echo '{}' | CLAUDE_AGENT_ID=a1 PATH="$STUB_DIR:$PATH" bash "$HOOKS/cmm-session-start.sh" >/dev/null 2>&1)
[ ! -f "$PIDFILE" ] && _pass "3: no indexer launched for an agent session" || _fail "3: agent session launched an indexer"

# --- 4. Agent gate holds the spawn only while a live indexer runs ---
echo "--- 4: agent gate waits on a live indexer, not a dead one ---"
GATE_IN='{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Use search_graph to find X"}}'
run_gate() { (cd "$FAKE_ROOT" && echo "$GATE_IN" | env "$@" bash "$HOOKS/agent-cmm-gate.sh" >/dev/null 2>&1); }

sleep 2 & LIVE=$!
echo "$LIVE" > "$PIDFILE"
T0=$(date +%s); run_gate CMM_AGENT_GATE_WAIT_SECS=10; RC=$?; T1=$(date +%s)
[ $((T1 - T0)) -ge 1 ] && _pass "4a: waited for the live indexer" || _fail "4a: did not wait ($((T1 - T0)) s)"
[ $((T1 - T0)) -lt 6 ] && _pass "4b: released when the indexer exited" || _fail "4b: waited past indexer exit"
[ "$RC" -eq 0 ] && _pass "4c: CMM-referencing prompt still allowed after wait" || _fail "4c: exit $RC"

sleep 5 & LIVE=$!
echo "$LIVE" > "$PIDFILE"
T0=$(date +%s); run_gate CMM_AGENT_GATE_WAIT_SECS=1; T1=$(date +%s)
kill "$LIVE" 2>/dev/null
[ $((T1 - T0)) -lt 3 ] && _pass "4d: wait is bounded by CMM_AGENT_GATE_WAIT_SECS" || _fail "4d: wait exceeded bound ($((T1 - T0)) s)"

echo 999999 > "$PIDFILE"
T0=$(date +%s); run_gate; T1=$(date +%s)
[ $((T1 - T0)) -lt 1 ] && _pass "4e: dead PID does not wait" || _fail "4e: waited on a dead PID"
rm -f "$PIDFILE"

# --- 5. Subagent guidance: concrete, project-filled, no state, no fallback ---
echo "--- 5: subagent injection is guidance only ---"
echo ready > "$CTX_SENTINEL"
OUT="$(cd "$FAKE_ROOT" && echo '{}' | bash "$HOOKS/subagent-cmm-startup.sh")"
CTX="$(printf '%s' "$OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
printf '%s' "$CTX" | grep -qF "project=\"$PROJECT\"" && _pass "5a: resolved project= filled in" || _fail "5a: project= missing"
printf '%s' "$CTX" | grep -qF "repo_path=\"$ROOT\"" && _pass "5b: repo_path filled in" || _fail "5b: repo_path missing"
for bad in grep '⚠' stale building; do
  printf '%s' "$CTX" | grep -qiF "$bad" && _fail "5c: injection contains '$bad'" || _pass "5c: injection free of '$bad'"
done
printf '%s' "$CTX" | grep -qF "ctx_execute" && _pass "5d: ctx line present when context-mode is installed" || _fail "5d: ctx line missing"
rm -f "$CTX_SENTINEL"
CTX="$(cd "$FAKE_ROOT" && echo '{}' | bash "$HOOKS/subagent-cmm-startup.sh" | python3 -c 'import sys,json; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
printf '%s' "$CTX" | grep -qF "ctx_execute" && _fail "5e: ctx line present without context-mode" || _pass "5e: ctx line omitted without context-mode"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
