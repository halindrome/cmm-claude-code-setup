#!/bin/bash
# test-vbw2-enforcer.sh — ctx-execute-enforcer.sh exemptions for VBW 2 (R2)
# Covers the 11 field cases from worker-simulator todo c4e1b7a2 plus the `;`,
# backtick and redirect cases: vbw:* agents (keyed on the PreToolUse input's
# agent_type) and bare `vbw` CLI calls pass; the main thread, other agents and
# compound/redirected vbw commands are still enforced.
# Usage: bash tests/test-vbw2-enforcer.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC_HOOK="$SCRIPT_DIR/../hooks/project/ctx-execute-enforcer.sh"

PASS=0
FAIL=0
_pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}
_fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

# Isolated fake repo (same layout as tests/test-ctx-execute-enforcer.sh): the
# hook resolves PROJECT_ROOT from the cwd and checks it against its own path,
# so it is copied into the fake repo. HOME is a scratch dir so the
# track-hook-blocks.sh counter file never touches the real ~/.cache.
FAKE_ROOT="$(mktemp -d)"
FAKE_ROOT="$(cd "$FAKE_ROOT" && pwd -P)"
FAKE_PROJ="$FAKE_ROOT/proj"
FAKE_HOME="$FAKE_ROOT/home"
mkdir -p "$FAKE_PROJ/hooks/project" "$FAKE_PROJ/hooks/lib" "$FAKE_HOME"
git -C "$FAKE_PROJ" init -q
cp "$SRC_HOOK" "$FAKE_PROJ/hooks/project/ctx-execute-enforcer.sh"
cp "$SCRIPT_DIR/../hooks/project/track-hook-blocks.sh" "$FAKE_PROJ/hooks/project/track-hook-blocks.sh"
cp "$SCRIPT_DIR/../hooks/lib/"*.sh "$FAKE_PROJ/hooks/lib/" 2>/dev/null || true
HOOK="$FAKE_PROJ/hooks/project/ctx-execute-enforcer.sh"

_md5() { if command -v md5 >/dev/null 2>&1; then md5 -q; else md5sum | awk '{print $1}'; fi; }
PROJECT_HASH="$(echo "$FAKE_PROJ" | _md5)"
CM_CACHE="/tmp/ctx-enforcer-${PROJECT_HASH}"
CM_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"
COUNTER="$FAKE_HOME/.cache/codebase-memory-mcp/_block-counts-${PROJECT_HASH}.json"

_cleanup() {
    rm -rf "$FAKE_ROOT"
    rm -f "$CM_CACHE" "$CM_SENTINEL"
    rm -f "/tmp/cmm-project-root-$(echo -n "$FAKE_PROJ" | _md5)"
}
trap _cleanup EXIT

# Context Mode installed and proven live, so the enforcer is armed.
echo "1" >"$CM_CACHE"
echo "live" >"$CM_SENTINEL"

# A syntax error exits 2 (the block code) and would keep every block case green.
if bash -n "$HOOK" 2>/dev/null; then
    _pass "hook parses (bash -n)"
else
    _fail "hook has a syntax error"
fi

# _json <command> [agent_type-json-value]  -> PreToolUse Bash input
# The second argument is a raw JSON value (e.g. '"vbw:dev"', 'null', '123');
# omit it for an input with no agent_type field (the main thread).
_json() {
    CMD="$1" AT="${2-__absent__}" python3 -c '
import json, os
d = {"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}
at = os.environ["AT"]
if at != "__absent__":
    d["agent_type"] = json.loads(at)
print(json.dumps(d))'
}

_run() {
    local rc=0
    printf '%s' "$1" | (cd "$FAKE_PROJ" && HOME="$FAKE_HOME" bash "$HOOK") >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

_expect() {
    local label="$1" want="$2" input="$3" got
    got="$(_run "$input")"
    if [ "$got" = "$want" ]; then _pass "$label"; else _fail "$label (expected exit $want, got $got)"; fi
}

_allows() {
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); raise SystemExit
print(d.get("allows", {}).get(sys.argv[2], 0))' "$COUNTER" "$1"
}

echo "--- vbw:* agents: any command passes, compound included ---"
_expect "agent_type vbw:dev pytest -> allow" 0 "$(_json 'pytest' '"vbw:dev"')"
_expect "agent_type vbw:qa 'cd x && mypy' -> allow" 0 "$(_json 'cd x && mypy' '"vbw:qa"')"
_expect "agent_type vbw:dev 'npm test | tail -5' -> allow (before compound check)" 0 \
    "$(_json 'npm test | tail -5' '"vbw:dev"')"
_expect "agent_type vbw:scout 'ruff check . ; mypy src' -> allow" 0 "$(_json 'ruff check . ; mypy src' '"vbw:scout"')"

echo "--- bare vbw CLI calls pass from any caller ---"
_expect "main thread 'vbw show contract' -> allow" 0 "$(_json 'vbw show contract')"
_expect "main thread 'VBW_SESSION_ID=abc vbw next --json' -> allow" 0 "$(_json 'VBW_SESSION_ID=abc vbw next --json')"
_expect "main thread '/abs/path/vbw prove' -> allow" 0 "$(_json '/abs/path/vbw prove')"
_expect "agent_type Explore 'vbw show contract' -> allow" 0 "$(_json 'vbw show contract' '"Explore"')"

echo "--- still enforced: main thread and other agents ---"
_expect "main thread pytest -> block" 2 "$(_json 'pytest')"
_expect "agent_type Explore 'cat src/main.py' -> block" 2 "$(_json 'cat src/main.py' '"Explore"')"
_expect "agent_type general-purpose 'npm test' -> block" 2 "$(_json 'npm test' '"general-purpose"')"

echo "--- still enforced: compound, substituted and redirected vbw commands ---"
_expect "'vbw next | jq .' -> block" 2 "$(_json 'vbw next | jq .')"
_expect "'vbw show contract && cat f' -> block" 2 "$(_json 'vbw show contract && cat f')"
_expect "'vbw show contract; pytest' -> block" 2 "$(_json 'vbw show contract; pytest')"
_expect "'vbw decide \$(cat f)' -> block" 2 "$(_json 'vbw decide $(cat f)')"
_expect "'vbw decide \`cat f\`' -> block" 2 "$(_json 'vbw decide `cat f`')"
_expect "'vbw show contract > f' -> block" 2 "$(_json 'vbw show contract > f')"
_expect "'vbwx foo' (name-prefix lookalike) -> block" 2 "$(_json 'vbwx foo')"
_expect "'vbw decide \"\$(cat f)\"' (live inside double quotes) -> block" 2 "$(_json 'vbw decide "$(cat f)"')"
_expect "'vbw decide \"a\" ; rm x' (operator outside quotes) -> block" 2 "$(_json 'vbw decide "a" ; rm x')"
_expect "'vbw decide \"a\" > f' (redirect outside quotes) -> block" 2 "$(_json 'vbw decide "a" > f')"
_expect "escaped quote pairing 'vbw x \\'; rm y; echo \\'' -> block" 2 "$(_json "vbw x \\'; rm y; echo \\'")"

echo "--- quoted vbw arguments are literal text ---"
_expect "'vbw todo add \"fix (a); b\"' -> allow" 0 "$(_json 'vbw todo add "fix (a); b"')"
_expect "vbw decide with ( ) ' | in quotes -> allow" 0 "$(_json "vbw decide 'use X (not Y)' \"why: it's | fine\"")"

echo "--- VBW 1 agent types are not VBW 2 agents ---"
_expect "agent_type vbw:vbw-dev pytest -> block" 2 "$(_json 'pytest' '"vbw:vbw-dev"')"

echo "--- missing, empty or malformed agent_type falls through to normal enforcement ---"
_expect "agent_type absent pytest -> block" 2 "$(_json 'pytest')"
_expect "agent_type empty string pytest -> block" 2 "$(_json 'pytest' '""')"
_expect "agent_type null pytest -> block" 2 "$(_json 'pytest' 'null')"
_expect "agent_type number pytest -> block" 2 "$(_json 'pytest' '123')"
_expect "agent_type object pytest -> block" 2 "$(_json 'pytest' '{"x":"vbw:dev"}')"
_expect "agent_type 'vbw' (no colon) pytest -> block" 2 "$(_json 'pytest' '"vbw"')"
_expect "agent_type 'vbwx:dev' pytest -> block" 2 "$(_json 'pytest' '"vbwx:dev"')"
_expect "agent_type null 'git status' -> normal exemption still applies" 0 "$(_json 'git status' 'null')"

echo "--- each exemption is logged with its own reason ---"
rm -f "$COUNTER"
_run "$(_json 'pytest' '"vbw:dev"')" >/dev/null
if [ "$(_allows ctx-execute-enforcer-exempt-vbw-agent)" = "1" ] &&
    [ "$(_allows ctx-execute-enforcer-exempt-vbw-cli)" = "0" ]; then
    _pass "vbw:* agent exemption logged as vbw-agent"
else
    _fail "vbw:* agent exemption not logged as vbw-agent (counter: $(cat "$COUNTER" 2>/dev/null | tr -d '\n'))"
fi
rm -f "$COUNTER"
_run "$(_json 'vbw show contract')" >/dev/null
if [ "$(_allows ctx-execute-enforcer-exempt-vbw-cli)" = "1" ] &&
    [ "$(_allows ctx-execute-enforcer-exempt-vbw-agent)" = "0" ]; then
    _pass "bare vbw CLI exemption logged as vbw-cli"
else
    _fail "bare vbw CLI exemption not logged as vbw-cli (counter: $(cat "$COUNTER" 2>/dev/null | tr -d '\n'))"
fi

echo "--- VBW 1 allowlist entries keep their behavior ---"
_expect "bash */.vbw-planning/* script -> allow" 0 "$(_json 'bash /Users/x/proj/.vbw-planning/scripts/state.sh')"
_expect "/tmp/.vbw-plugin-root-link-* script -> allow" 0 "$(_json '/tmp/.vbw-plugin-root-link-abc/scripts/run.sh')"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
