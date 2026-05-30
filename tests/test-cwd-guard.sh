#!/bin/bash
# test-cwd-guard.sh — Tests cwd-guard.sh persistent-cd prevention.
# Verifies that a top-level persistent `cd` away from the project root is blocked
# (exit 2), while absolute paths, git -C, subshell cd, re-anchoring to root, and
# the `# cwd-exempt` bypass are allowed (exit 0). Fail-open on malformed input.
# Usage: bash tests/test-cwd-guard.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/cwd-guard.sh"

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Setup: fake git repo so the hook's inline root detection resolves to FAKE_ROOT.
FAKE_ROOT=$(mktemp -d /tmp/cmm-cwdtest-XXXXXX)
FAKE_ROOT="$(cd "$FAKE_ROOT" && pwd -P)"
git -C "$FAKE_ROOT" init -q
git -C "$FAKE_ROOT" commit --allow-empty -q -m "init"
mkdir -p "$FAKE_ROOT/hooks/project" "$FAKE_ROOT/apps/rest-api"
# Copy the hook WITHOUT the lib so it uses inline fallback detection (git toplevel
# from CWD), keeping the test deterministic and independent of the repo's lib cache.
cp "$HOOK" "$FAKE_ROOT/hooks/project/cwd-guard.sh"
HOOK="$FAKE_ROOT/hooks/project/cwd-guard.sh"

# _run <expected> <label> <command-string>
_run() {
    local expected="$1" label="$2" cmd="$3"
    local json exit_code=0
    json=$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.stdin.read()}}))')
    printf '%s' "$json" | (cd "$FAKE_ROOT" && bash "$HOOK") >/dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq "$expected" ]; then
        _pass "$label"
    else
        _fail "$label (expected exit $expected, got $exit_code)"
    fi
}

# --- BLOCK: persistent top-level cd away from root ---
_run 2 "persistent cd into subdir blocked"            'cd apps/rest-api'
_run 2 "cd subdir then && cmd blocked"                'cd apps/rest-api && make test'
_run 2 "bare cd (to HOME) blocked"                    'cd'
_run 2 "cd relative .. blocked"                       'cd ..'

# --- ALLOW: cwd-independent or root-anchoring forms ---
_run 0 "re-anchor to absolute root allowed"           "cd $FAKE_ROOT"
_run 0 "cd . allowed (root)"                          'cd .'
_run 0 "subshell cd is local, allowed"                '( cd apps/rest-api && make test )'
_run 0 "git -C per-repo allowed"                      'git -C apps/rest-api status'
_run 0 "absolute-path command (no cd) allowed"        'cat /etc/hosts'
_run 0 "command with no cd allowed"                   'npm test'
_run 0 "cwd-exempt bypass allowed"                    'cd apps/rest-api  # cwd-exempt'
_run 0 "command substitution cd is local, allowed"    'echo "$(cd apps && pwd)"'

# --- Fail-open: malformed / empty input must never wedge Bash ---
EXIT_CODE=0
printf '%s' 'not json' | (cd "$FAKE_ROOT" && bash "$HOOK") >/dev/null 2>&1 || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then _pass "malformed JSON fail-open (exit 0)"; else _fail "malformed JSON should fail-open (got $EXIT_CODE)"; fi

EXIT_CODE=0
printf '%s' '{"tool_name":"Bash","tool_input":{"command":""}}' | (cd "$FAKE_ROOT" && bash "$HOOK") >/dev/null 2>&1 || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then _pass "empty command fail-open (exit 0)"; else _fail "empty command should fail-open (got $EXIT_CODE)"; fi

rm -rf "$FAKE_ROOT"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
