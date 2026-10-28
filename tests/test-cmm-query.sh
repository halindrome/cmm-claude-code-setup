#!/bin/bash
# test-cmm-query.sh — the CMM CLI wrapper hooks/project/cmm-query.sh (R5)
# A vbw:* agent has Bash but no MCP tools, so it reaches the CMM graph through
# `bash <root>/.claude/hooks/cmm-query.sh <tool> '<json>'`. This pins the
# wrapper's tool allowlist, project injection (monorepo root), --quiet, its
# error messages, the session-ready sentinel it writes after indexing, that
# VBW 2's own guard-bash.jq does not refuse it during a run, and (when the CMM
# binary exists) real results for the four query tools.
# Usage: bash tests/test-cmm-query.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SRC="$REPO/hooks/project/cmm-query.sh"

PASS=0
FAIL=0
SKIP=0
_pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}
_fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}
_skip() {
    echo "SKIP: $1"
    SKIP=$((SKIP + 1))
}
_md5() { if command -v md5 >/dev/null 2>&1; then md5 -q; else md5sum | awk '{print $1}'; fi; }

REAL_CMM="$(command -v codebase-memory-mcp 2>/dev/null || true)"
T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
CLEANUP_PROJECTS=()
_cleanup() {
    local p r
    for p in "${CLEANUP_PROJECTS[@]+"${CLEANUP_PROJECTS[@]}"}"; do
        "$REAL_CMM" cli --quiet delete_project "{\"project\":\"$p\"}" >/dev/null 2>&1 || true
    done
    for r in "$T/repo" "$T/mono" "$T/live"; do
        rm -f "/tmp/cmm-session-ready-$(echo "$r" | _md5)" "/tmp/cmm-indexing-$(echo "$r" | _md5)"
    done
    for d in "$T/repo" "$T/repo/src" "$T/mono" "$T/mono/sub" "$T/mono/sub/pkg" "$T/live"; do
        rm -f "/tmp/cmm-project-root-$(echo -n "$d" | _md5)"
    done
    rm -rf "$T"
}
trap _cleanup EXIT

# _install <repo>: the installed layout (.claude/hooks/cmm-query.sh + lib/)
_install() {
    mkdir -p "$1/.claude/hooks/lib"
    [ -f "$SRC" ] && cp "$SRC" "$1/.claude/hooks/cmm-query.sh"
    cp "$REPO/hooks/lib/"*.sh "$1/.claude/hooks/lib/"
}

# Stub CMM: records its argv as JSON and answers per STUB_MODE.
mkdir -p "$T/bin" "$T/nobin"
cat >"$T/bin/codebase-memory-mcp" <<'PY'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["STUB_LOG"], "w") as f:
    json.dump(sys.argv[1:], f)
if os.environ.get("STUB_MODE") == "notindexed":
    print('{"error":"project not found or not indexed","hint":"Use list_projects"}')
    sys.exit(1)
print("results: 1\n  stub.result Function src/a.py 1-2 0 0")
PY
chmod +x "$T/bin/codebase-memory-mcp"
STUB_LOG="$T/stub.json"
# PATH for "CLI missing": the system tools the wrapper needs, minus any CMM binary.
NOCMM_PATH="$T/nobin"
IFS=':' read -ra _P <<<"$PATH"
for d in "${_P[@]}"; do
    [ -n "$d" ] && [ ! -x "$d/codebase-memory-mcp" ] && NOCMM_PATH="$NOCMM_PATH:$d"
done

# _q <cwd> <path-prefix> <args...> -> sets RC and OUT (stdout+stderr)
_q() {
    local cwd="$1" path="$2"
    shift 2
    rm -f "$STUB_LOG"
    RC=0
    OUT="$(cd "$cwd" && PATH="$path" STUB_LOG="$STUB_LOG" STUB_MODE="${STUB_MODE:-ok}" bash ./.claude/hooks/cmm-query.sh "$@" 2>&1)" || RC=$?
}
# Same, from a subdirectory: the wrapper is called by absolute path.
_qabs() {
    local cwd="$1" wrapper="$2" path="$3"
    shift 3
    rm -f "$STUB_LOG"
    RC=0
    OUT="$(cd "$cwd" && PATH="$path" STUB_LOG="$STUB_LOG" STUB_MODE="${STUB_MODE:-ok}" bash "$wrapper" "$@" 2>&1)" || RC=$?
}
# _argv <python-expr over a=argv list, j=parsed json arg or None>
_argv() {
    python3 - "$STUB_LOG" "$1" <<'PY' 2>/dev/null || echo "no-call"
import json, sys
a = json.load(open(sys.argv[1]))
j = None
for x in a:
    try:
        v = json.loads(x)
    except Exception:
        continue
    if isinstance(v, dict):
        j = v
print(eval(sys.argv[2]))
PY
}
_projname() { (PROJECT_ROOT="$1" bash -c 'source "$0"; cmm_project_name' "$REPO/hooks/lib/cmm-registered.sh"); }

# Fixture repo
mkdir -p "$T/repo/src"
git -C "$T/repo" init -q
_install "$T/repo"
PROJ="$(_projname "$T/repo")"
PATH_STUB="$T/bin:$PATH"

if [ -f "$SRC" ]; then _pass "hooks/project/cmm-query.sh exists"; else _fail "hooks/project/cmm-query.sh missing"; fi

echo "--- allowed tools pass through with --quiet and the injected project ---"
for tool in search_graph trace_path get_code_snippet search_code query_graph get_architecture index_status; do
    _q "$T/repo" "$PATH_STUB" "$tool" '{"name_pattern":"x"}'
    if [ "$RC" = 0 ] && [ "$(_argv "a[0]=='cli' and '--quiet' in a and '$tool' in a and j is not None and j.get('project')=='$PROJ'")" = "True" ]; then
        _pass "$tool -> codebase-memory-mcp cli --quiet $tool {project: $PROJ}"
    else
        _fail "$tool not passed through with --quiet and project=$PROJ (rc=$RC, argv=$(cat "$STUB_LOG" 2>/dev/null || echo none))"
    fi
done
_q "$T/repo" "$PATH_STUB" search_graph '{"name_pattern":"helper","label":"Function"}'
if [ "$(_argv "j.get('name_pattern')=='helper' and j.get('label')=='Function'")" = "True" ]; then
    _pass "caller's JSON arguments are kept"
else
    _fail "caller's JSON arguments were not kept (argv=$(cat "$STUB_LOG" 2>/dev/null || echo none))"
fi
_q "$T/repo" "$PATH_STUB" list_projects
if [ "$RC" = 0 ] && [ "$(_argv "'list_projects' in a and '--quiet' in a")" = "True" ]; then
    _pass "list_projects allowed"
else
    _fail "list_projects not allowed (rc=$RC)"
fi
_q "$T/repo" "$PATH_STUB" index_repository
if [ "$RC" = 0 ] && [ "$(_argv "'index_repository' in a and j is not None and j.get('repo_path')=='$T/repo'")" = "True" ]; then
    _pass "index_repository allowed, repo_path=<project root> injected"
else
    _fail "index_repository not run with repo_path=$T/repo (rc=$RC, argv=$(cat "$STUB_LOG" 2>/dev/null || echo none))"
fi

echo "--- project comes from the monorepo/superproject root, from any cwd ---"
mkdir -p "$T/subsrc"
git -C "$T/subsrc" init -q
git -C "$T/subsrc" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$T/mono"
git -C "$T/mono" init -q
git -C "$T/mono" -c protocol.file.allow=always submodule add -q "$T/subsrc" sub >/dev/null 2>&1
mkdir -p "$T/mono/sub/pkg"
_install "$T/mono"
MONO="$(_projname "$T/mono")"
_qabs "$T/mono/sub/pkg" "$T/mono/.claude/hooks/cmm-query.sh" "$PATH_STUB" search_graph '{"name_pattern":"x"}'
if [ "$(_argv "j is not None and j.get('project')=='$MONO'")" = "True" ]; then
    _pass "cwd inside a submodule -> superproject project $MONO"
else
    _fail "cwd inside a submodule did not resolve to $MONO (argv=$(cat "$STUB_LOG" 2>/dev/null || echo none))"
fi
_qabs "$T/repo/src" "$T/repo/.claude/hooks/cmm-query.sh" "$PATH_STUB" search_code '{"pattern":"x"}'
if [ "$(_argv "j is not None and j.get('project')=='$PROJ'")" = "True" ]; then
    _pass "cwd in a subdirectory -> repo root project"
else
    _fail "cwd in a subdirectory did not resolve to $PROJ"
fi

echo "--- refusals ---"
_q "$T/repo" "$PATH_STUB" delete_project '{"project":"x"}'
if [ "$RC" != 0 ] && [ ! -f "$STUB_LOG" ] && printf '%s' "$OUT" | grep -q search_graph && printf '%s' "$OUT" | grep -q index_repository; then
    _pass "delete_project refused, allowed tools listed, CMM not called"
else
    _fail "delete_project not refused with the allowed-tool list (rc=$RC, out=$OUT)"
fi
_q "$T/repo" "$PATH_STUB"
if [ "$RC" != 0 ] && [ ! -f "$STUB_LOG" ]; then _pass "no tool name -> non-zero"; else _fail "no tool name accepted (rc=$RC)"; fi
for bad in '{"name_pattern":' 'notjson' '[1,2]'; do
    _q "$T/repo" "$PATH_STUB" search_graph "$bad"
    if [ "$RC" != 0 ] && [ -n "$OUT" ] && [ ! -f "$STUB_LOG" ]; then
        _pass "malformed JSON args '$bad' -> non-zero with an error, CMM not called"
    else
        _fail "malformed JSON args '$bad' not refused (rc=$RC, out=$OUT)"
    fi
done

echo "--- CLI missing / project not indexed ---"
_q "$T/repo" "$NOCMM_PATH" search_graph '{"name_pattern":"x"}'
if [ "$RC" != 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ] && printf '%s' "$OUT" | grep -q codebase-memory-mcp; then
    _pass "CMM CLI not on PATH -> non-zero, one line naming codebase-memory-mcp"
else
    _fail "CMM CLI missing not reported as one line (rc=$RC, out=$OUT)"
fi
STUB_MODE=notindexed _q "$T/repo" "$PATH_STUB" search_graph '{"name_pattern":"x"}'
SUGGEST="$(printf '%s\n' "$OUT" | grep -Eo 'bash [^ ]*cmm-query\.sh index_repository' | head -1 || true)"
if [ "$RC" != 0 ] && printf '%s' "$OUT" | grep -qi 'not indexed' && [ -n "$SUGGEST" ]; then
    _pass "unindexed project -> says so and names: $SUGGEST"
else
    _fail "unindexed project not reported with the index_repository wrapper command (rc=$RC, out=$OUT)"
fi

echo "--- indexing through the wrapper opens the session gate ---"
HASH="$(echo "$T/repo" | _md5)"
rm -f "/tmp/cmm-session-ready-$HASH"
echo x >"/tmp/cmm-indexing-$HASH"
_q "$T/repo" "$PATH_STUB" index_repository
if [ "$RC" = 0 ] && grep -q '^ready$' "/tmp/cmm-session-ready-$HASH" 2>/dev/null && [ ! -e "/tmp/cmm-indexing-$HASH" ]; then
    _pass "index_repository success writes the session-ready sentinel and clears the indexing marker"
else
    _fail "index_repository did not write /tmp/cmm-session-ready-<hash> (rc=$RC)"
fi
rm -f "/tmp/cmm-session-ready-$HASH"
STUB_MODE=notindexed _q "$T/repo" "$PATH_STUB" index_repository
if [ ! -e "/tmp/cmm-session-ready-$HASH" ]; then
    _pass "failed index_repository writes no sentinel"
else
    _fail "failed index_repository still wrote the sentinel"
fi

echo "--- VBW 2 guard-bash.jq does not refuse a wrapper call during a run ---"
GUARD=""
for c in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do
    [ -n "$c" ] || continue
    for g in "$c"/plugins/cache/vbw-marketplace/vbw/2.*/hooks/guard-bash.jq; do [ -f "$g" ] && GUARD="$g"; done
done
if [ -z "$GUARD" ] || ! command -v jq >/dev/null 2>&1; then
    _skip "VBW 2 plugin (guard-bash.jq) or jq not installed"
elif [ -z "$SUGGEST" ]; then
    _fail "no wrapper command line to feed the guard (see the unindexed case)"
else
    GH="$(dirname "$GUARD")"
    mkdir -p "$T/repo/.vbw/runtime"
    : >"$T/repo/.vbw/runtime/run-open"
    python3 - "$T/repo/.vbw/record.json" <<'PY'
import json, sys, time
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
json.dump({"lease": {"run": "build-t", "kind": "build", "started_at": now,
                     "files": ["src/a.py"], "session": "s1"}, "protected": []},
          open(sys.argv[1], "w"))
PY
    _guard() {
        CMD="$1" R="$T/repo" python3 -c 'import json,os; print(json.dumps({"tool_name":"Bash","agent_type":"vbw:dev","session_id":"s1","cwd":os.environ["R"],"tool_input":{"command":os.environ["CMD"]}}))' |
            jq -nc --rawfile glance /dev/null --arg root "$T/repo" --arg dir "$T/repo" --arg open 1 \
                -f "$GUARD" - "$T/repo/.vbw/record.json" "$GH/end.json" 2>&1 || true
    }
    if printf '%s' "$(_guard 'git commit -m x')" | grep -q 'VBW guard'; then
        _pass "guard fixture is armed (a builder's git commit is refused)"
    else
        _fail "guard fixture is not armed; the cases below would prove nothing"
    fi
    for cmd in "$SUGGEST" "${SUGGEST% index_repository} search_graph '{\"name_pattern\":\"x\"}'"; do
        if [ -z "$(_guard "$cmd")" ]; then _pass "guard allows: $cmd"; else _fail "guard refused: $cmd -> $(_guard "$cmd")"; fi
    done
fi

echo "--- real results for the four query tools (needs the CMM binary) ---"
if [ -z "$REAL_CMM" ]; then
    _skip "codebase-memory-mcp not on PATH: live wrapper queries not run"
else
    mkdir -p "$T/live/src"
    printf 'def helper():\n    return "needle-literal"\n\n\ndef main():\n    return helper()\n' >"$T/live/src/app.py"
    git -C "$T/live" init -q
    _install "$T/live"
    CLEANUP_PROJECTS+=("$(_projname "$T/live")")
    _q "$T/live" "$PATH" index_repository
    if [ "$RC" = 0 ]; then _pass "live: index_repository via wrapper"; else _fail "live: index_repository failed (rc=$RC, out=$OUT)"; fi
    _live() {
        local tool="$1" args="$2" want="$3"
        _q "$T/live" "$PATH" "$tool" "$args"
        if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q -- "$want" && ! printf '%s' "$OUT" | grep -q '"error"'; then
            _pass "live: $tool returns results ($want)"
        else
            _fail "live: $tool returned no results (rc=$RC, out=$(printf '%s' "$OUT" | head -c 300))"
        fi
    }
    _live search_graph '{"name_pattern":"helper"}' 'src.app.helper'
    _live trace_path '{"function_name":"helper","direction":"inbound"}' 'src.app.main'
    _live get_code_snippet '{"qualified_name":"helper"}' 'needle-literal'
    _live search_code '{"pattern":"needle-literal"}' 'src/app.py'
fi

echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
