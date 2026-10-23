#!/bin/bash
# test-hook-driven-indexing.sh — hooks refresh the CMM index; subagents get guidance, not state
# Covers: cmm-session-start.sh background index launch, agent-cmm-gate.sh spawn hold,
# subagent-cmm-startup.sh guidance text, cmm_project_name (hooks/lib/cmm-registered.sh).
# Usage: bash tests/test-hook-driven-indexing.sh
# Exit: 0 = all pass, 1 = any failure
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC="${HDI_HOOKS_SRC:-$SCRIPT_DIR/../hooks}"

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
# Millisecond clock: whole-second `date +%s` deltas flip on second boundaries.
_now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

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
BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"   # no codebase-memory-mcp on it

# Stub CLI: records its argv, sleeps STUB_SLEEP (default 1 s), then prints an
# "indexed" result — or fails when STUB_FAIL=1.
_make_stub() {
  mkdir -p "$1"
  cat > "$1/codebase-memory-mcp" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$(dirname "$0")/argv"
python3 -c 'import os,sys; sys.exit(not os.path.samestat(os.fstat(0), os.stat("/dev/null")))' \
  && echo devnull > "$(dirname "$0")/stdin" || echo other > "$(dirname "$0")/stdin"
sleep "${STUB_SLEEP:-1}"
[ "${STUB_FAIL:-0}" = "1" ] && { echo '{"error":"version conflict"}'; exit 1; }
echo '{"project":"x","status":"indexed"}'
STUB
  chmod +x "$1/codebase-memory-mcp"
}
STUB_DIR="$FAKE_ROOT/stub"
_make_stub "$STUB_DIR"
FAKE_HOME="$FAKE_ROOT/home"
_make_stub "$FAKE_HOME/.local/bin"
EMPTY_HOME="$FAKE_ROOT/empty-home"
mkdir -p "$EMPTY_HOME"

cleanup() { rm -rf "$FAKE_ROOT"; rm -f "$SENTINEL" "$MARKER" "$PIDFILE" "$CTX_SENTINEL"; }
trap cleanup EXIT

_wait_gone() { for _ in $(seq 1 40); do [ -f "$1" ] || return 0; sleep 0.25; done; return 1; }

run_start() { (cd "$FAKE_ROOT" && echo '{}' | env -u CLAUDE_AGENT_ID -u CLAUDE_PARENT_SESSION_ID "$@" bash "$HOOKS/cmm-session-start.sh" >/dev/null 2>&1); }

# --- 1. Session start returns immediately and the background job opens the gate ---
echo "--- 1: session start launches a detached index refresh ---"
rm -f "$SENTINEL" "$PIDFILE" "$STUB_DIR/argv"
run_start PATH="$STUB_DIR:$PATH"
[ -f "$PIDFILE" ] && _pass "1a: indexer PID recorded" || _fail "1a: no PID file"
kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null \
  && _pass "1b: hook returned while the indexer was still running" \
  || _fail "1b: indexer already gone when hook returned (hook waited on it?)"
_wait_gone "$PIDFILE" && _pass "1c: PID file removed when indexer exits" || _fail "1c: PID file left behind"
grep -qx ready "$SENTINEL" 2>/dev/null && _pass "1d: sentinel written as ready" || _fail "1d: sentinel not ready"
[ ! -f "$MARKER" ] && _pass "1e: indexing marker cleared" || _fail "1e: indexing marker still present"
ARGV="$(tr '\n' ' ' < "$STUB_DIR/argv" 2>/dev/null)"
case "$ARGV" in
  *"index_repository --repo-path $ROOT "*) _pass "1f: CLI called as index_repository --repo-path <root>" ;;
  *) _fail "1f: unexpected CLI argv: $ARGV" ;;
esac
# Outcome check only: a non-interactive bash already gives `cmd &` stdin from
# /dev/null (POSIX async lists), so dropping the hook's `</dev/null` stays green.
grep -qx devnull "$STUB_DIR/stdin" 2>/dev/null && _pass "1h: indexer stdin is /dev/null (not the hook's stdin)" \
  || _fail "1h: indexer inherited a non-/dev/null stdin"

# --- 1g. Detached: the background job must not hold the hook's stdout/stderr ---
# Capturing the hook's output waits for EVERY writer of the pipe to exit. If the
# job inherited stdout or stderr, $(…) blocks for the stub's full 4 s sleep.
echo "--- 1g: background job does not hold the hook's output pipes ---"
rm -f "$SENTINEL" "$PIDFILE"
T0=$(_now_ms)
_OUT="$(cd "$FAKE_ROOT" && echo '{}' | env -u CLAUDE_AGENT_ID -u CLAUDE_PARENT_SESSION_ID PATH="$STUB_DIR:$PATH" STUB_SLEEP=4 bash "$HOOKS/cmm-session-start.sh" 2>&1)"
T1=$(_now_ms)
[ $((T1 - T0)) -lt 2500 ] && _pass "1g: hook output closed before the indexer finished ($((T1 - T0)) ms)" \
  || _fail "1g: capturing hook output waited $((T1 - T0)) ms — background job holds stdout/stderr"
_wait_gone "$PIDFILE"

# --- 2. A failed CLI run leaves the gate exactly as before ---
echo "--- 2: failing CLI leaves no sentinel and keeps the fail-open marker ---"
rm -f "$SENTINEL" "$PIDFILE"
run_start PATH="$STUB_DIR:$PATH" STUB_FAIL=1
_wait_gone "$PIDFILE" && _pass "2c: PID file removed after a failed run" || _fail "2c: PID file left behind after failure"
[ ! -f "$SENTINEL" ] && _pass "2a: no sentinel on failure" || _fail "2a: sentinel written despite failure"
[ -f "$MARKER" ] && _pass "2b: fail-open marker kept" || _fail "2b: marker removed on failure"

# --- 2d/2e. Binary resolution: $HOME/.local/bin fallback, and a silent skip without one ---
echo "--- 2d/2e: binary fallback and no-binary skip ---"
rm -f "$SENTINEL" "$PIDFILE"
run_start PATH="$BASE_PATH" HOME="$FAKE_HOME"
_wait_gone "$PIDFILE"
grep -qx ready "$SENTINEL" 2>/dev/null && [ -f "$FAKE_HOME/.local/bin/argv" ] \
  && _pass "2d: \$HOME/.local/bin fallback used when PATH has no binary" \
  || _fail "2d: fallback binary not used"
rm -f "$SENTINEL" "$PIDFILE"
run_start PATH="$BASE_PATH" HOME="$EMPTY_HOME"; RC=$?
[ "$RC" -eq 0 ] && [ ! -f "$PIDFILE" ] && [ ! -f "$SENTINEL" ] \
  && _pass "2e: no binary anywhere -> no launch, hook still exits 0" \
  || _fail "2e: no-binary case launched or failed (rc=$RC)"

# --- 3. Agent sessions never launch an indexer ---
echo "--- 3: agent session does not launch ---"
rm -f "$PIDFILE"
(cd "$FAKE_ROOT" && echo '{}' | CLAUDE_AGENT_ID=a1 PATH="$STUB_DIR:$PATH" bash "$HOOKS/cmm-session-start.sh" >/dev/null 2>&1)
[ ! -f "$PIDFILE" ] && _pass "3a: no indexer launched when CLAUDE_AGENT_ID is set" || _fail "3a: agent session launched an indexer"
rm -f "$PIDFILE"
(cd "$FAKE_ROOT" && echo '{}' | env -u CLAUDE_AGENT_ID CLAUDE_PARENT_SESSION_ID=p1 PATH="$STUB_DIR:$PATH" bash "$HOOKS/cmm-session-start.sh" >/dev/null 2>&1)
[ ! -f "$PIDFILE" ] && _pass "3b: no indexer launched when CLAUDE_PARENT_SESSION_ID is set" || _fail "3b: child session launched an indexer"
rm -f "$PIDFILE"

# --- 4. Agent gate holds the spawn only while a live indexer runs ---
echo "--- 4: agent gate waits on a live indexer, not a dead one ---"
GATE_IN='{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Use search_graph to find X"}}'
run_gate() { (cd "$FAKE_ROOT" && echo "$GATE_IN" | env "$@" bash "$HOOKS/agent-cmm-gate.sh" >/dev/null 2>&1); }

sleep 2 & LIVE=$!
echo "$LIVE" > "$PIDFILE"
T0=$(_now_ms); run_gate CMM_AGENT_GATE_WAIT_SECS=10; RC=$?; T1=$(_now_ms)
[ $((T1 - T0)) -ge 1000 ] && _pass "4a: waited for the live indexer" || _fail "4a: did not wait ($((T1 - T0)) ms)"
[ $((T1 - T0)) -lt 6000 ] && _pass "4b: released when the indexer exited" || _fail "4b: waited past indexer exit ($((T1 - T0)) ms)"
[ "$RC" -eq 0 ] && _pass "4c: CMM-referencing prompt still allowed after wait" || _fail "4c: exit $RC"

sleep 5 & LIVE=$!
echo "$LIVE" > "$PIDFILE"
T0=$(_now_ms); run_gate CMM_AGENT_GATE_WAIT_SECS=1; T1=$(_now_ms)
[ $((T1 - T0)) -lt 3000 ] && _pass "4d: wait is bounded by CMM_AGENT_GATE_WAIT_SECS" || _fail "4d: wait exceeded bound ($((T1 - T0)) ms)"

# Exempt built-in agent types are never held, even with a live indexer.
GATE_IN='{"tool_name":"Agent","tool_input":{"subagent_type":"claude-code-guide","prompt":"how do hooks work"}}'
T0=$(_now_ms); run_gate CMM_AGENT_GATE_WAIT_SECS=10; T1=$(_now_ms)
kill "$LIVE" 2>/dev/null
[ $((T1 - T0)) -lt 1500 ] && _pass "4f: exempt agent type not held by a live indexer" || _fail "4f: exempt type waited $((T1 - T0)) ms"
GATE_IN='{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Use search_graph to find X"}}'

# A dead PID must not wait — with the default 45 s bound, any wait at all shows.
echo 999999 > "$PIDFILE"
T0=$(_now_ms); run_gate; T1=$(_now_ms)
[ $((T1 - T0)) -lt 5000 ] && _pass "4e: dead PID does not wait" || _fail "4e: waited $((T1 - T0)) ms on a dead PID"
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
for s in "Invoke Skill('cmm-rules')" "Invoke Skill('ctx-rules')"; do
  printf '%s' "$CTX" | grep -qF "$s" && _pass "5f: emitted output has $s" || _fail "5f: emitted output lacks $s"
done
rm -f "$CTX_SENTINEL"
CTX="$(cd "$FAKE_ROOT" && echo '{}' | bash "$HOOKS/subagent-cmm-startup.sh" | python3 -c 'import sys,json; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
printf '%s' "$CTX" | grep -qF "ctx_execute" && _fail "5e: ctx line present without context-mode" || _pass "5e: ctx line omitted without context-mode"

# --- 6. cmm_project_name mirrors CMM's own naming (src/pipeline/fqn.c) ---
echo "--- 6: cmm_project_name normalises like CMM ---"
BASE="$(cd "$FAKE_ROOT" && pwd -P)"; BASE="${BASE#/}"; BASE="${BASE//\//-}"
_name() { (PROJECT_ROOT="$1"; source "$HOOKS/lib/cmm-registered.sh"; cmm_project_name); }
_check() {   # <dir under FAKE_ROOT> <expected suffix> <label>
  mkdir -p "$FAKE_ROOT/$1"
  local got; got="$(_name "$FAKE_ROOT/$1")"
  [ "$got" = "$BASE-$2" ] && _pass "6: $3" || _fail "6: $3 — got '$got', want '$BASE-$2'"
}
_check "My Projects/app" "My-Projects-app"   "space -> '-'"
_check "a@b+c"           "a-b-c"             "'@' and '+' -> '-'"
_check "x--y..z"         "x-y.z"             "runs of '-' and '.' collapsed"
_check "café"            "cafc3a9"           "non-ASCII bytes hex-encoded"
_check "trail-"          "trail"             "trailing '-' trimmed"
ln -s "$FAKE_ROOT/a@b+c" "$FAKE_ROOT/link"
[ "$(_name "$FAKE_ROOT/link")" = "$BASE-a-b-c" ] && _pass "6: symlinked root resolved before naming" \
  || _fail "6: symlink not resolved — got '$(_name "$FAKE_ROOT/link")'"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
