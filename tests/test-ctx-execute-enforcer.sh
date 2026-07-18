#!/bin/bash
# test-ctx-execute-enforcer.sh — Tests for ctx-execute-enforcer.sh large-output blocking
# Usage: bash tests/test-ctx-execute-enforcer.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/ctx-execute-enforcer.sh"

PASS=0; FAIL=0
_assert_exit() {
    local label="$1" expected="$2" json="$3"
    local actual=0
    echo "$json" | bash "$HOOK" >/dev/null 2>&1 || actual=$?
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL+1))
    fi
}

# --- Sentinel simulation setup ---
# Compute the same PROJECT_HASH the hook uses: md5 of canonical project root path
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
if command -v md5 >/dev/null 2>&1; then
    PROJECT_HASH="$(echo "$PROJECT_ROOT" | md5 -q)"
else
    PROJECT_HASH="$(echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')"
fi

CM_CACHE="/tmp/ctx-enforcer-${PROJECT_HASH}"
CM_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"

# This suite drives the hook against the REAL project hash, so $CM_CACHE and
# $CM_SENTINEL are the same files a live Claude Code session in this repo is
# using. Blindly rm-ing them on exit revoked the running session's Context Mode
# sentinel and wedged it mid-task. Snapshot whatever was there and put it back.
_CM_CACHE_BAK="$(mktemp)"; _CM_CACHE_EXISTED=false
_CM_SENT_BAK="$(mktemp)";  _CM_SENT_EXISTED=false
[ -f "$CM_CACHE" ]    && { cp "$CM_CACHE" "$_CM_CACHE_BAK";   _CM_CACHE_EXISTED=true; }
[ -f "$CM_SENTINEL" ] && { cp "$CM_SENTINEL" "$_CM_SENT_BAK"; _CM_SENT_EXISTED=true; }

_restore_sentinels() {
    if [ "$_CM_CACHE_EXISTED" = true ]; then cp "$_CM_CACHE_BAK" "$CM_CACHE"; else rm -f "$CM_CACHE"; fi
    if [ "$_CM_SENT_EXISTED" = true ];  then cp "$_CM_SENT_BAK" "$CM_SENTINEL"; else rm -f "$CM_SENTINEL"; fi
    rm -f "$_CM_CACHE_BAK" "$_CM_SENT_BAK"
}
trap _restore_sentinels EXIT

# Create sentinels to simulate Context Mode installed and ready
echo "1" > "$CM_CACHE"
touch "$CM_SENTINEL"

# Bail out early with a clear message if hook doesn't exist yet
if [ ! -f "$HOOK" ]; then
    echo ""
    echo "NOTE: $HOOK does not exist yet."
    echo "This test suite is complete but requires Plan 32-01 to be merged first."
    echo "Run again after hooks/project/ctx-execute-enforcer.sh is created."
    echo ""
    echo "Results: $PASS passed, $FAIL failed (hook not yet available)"
    exit 0
fi

# --- Blocked command tests (expect exit 2, sentinels present) ---
echo "--- Blocked command tests (sentinels present, expect exit 2) ---"

_assert_exit "npm test command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

_assert_exit "npx jest command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npx jest"}}'

_assert_exit "pip install command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"pip install requests"}}'

_assert_exit "eslint command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"eslint src/"}}'

_assert_exit "tail -f command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"tail -f /var/log/syslog"}}'

_assert_exit "npm run test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npm run test"}}'

_assert_exit "yarn run test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"yarn run test"}}'

_assert_exit "npx mocha blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npx mocha"}}'

_assert_exit "bun test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"bun test"}}'

_assert_exit "deno test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"deno test"}}'

_assert_exit "node --test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"node --test"}}'

_assert_exit "pnpm run test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"pnpm run test"}}'

# --- Exempt command tests (expect exit 0, sentinels present) ---
echo ""
echo "--- Exempt command tests (sentinels present, expect exit 0) ---"

_assert_exit "git commit exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add hook\""}}'

_assert_exit "mkdir exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"mkdir -p .claude/hooks"}}'

_assert_exit "date exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"date"}}'

_assert_exit "ls exempt (short-reads)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'

_assert_exit "bare ls exempt (short-reads)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

# Shell syntax checks (parse-only): no stdout on success, nothing to sandbox.
_assert_exit "bash -n script exempt (syntax-check)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"bash -n scripts/generate-checksums.sh"}}'

_assert_exit "sh -n script exempt (syntax-check)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"sh -n setup.sh"}}'

_assert_exit "bare bash -n exempt (syntax-check)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"bash -n"}}'

# But a compound that merely starts with a syntax check must still block.
_assert_exit "bash -n then && echo still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"bash -n x.sh && echo ok"}}'

# F-04 (Phase 61 round-1 follow-up): compound-shell detector must respect quoting.
# Operators inside single- or double-quoted argument strings are not real shell
# separators, so an otherwise-exempt single command (git commit, etc.) must not
# be false-positive blocked when its message/args contain `;`, `|`, `&&`, etc.
_assert_exit "git commit with quoted ; exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"wip; cleanup\""}}'

_assert_exit "git commit with quoted | exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"foo|bar\""}}'

# But unquoted compound operators must still block (defence in depth).
_assert_exit "unquoted git status && cat blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git status && cat /etc/passwd"}}'

_assert_exit "git status exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git status"}}'

# --- Git global-flag normalization (submodule / monorepo targeting) ---
# cwd-guard.sh instructs the agent to prefer `git -C <subrepo> <cmd>` over
# `cd <subrepo> && <cmd>`. The exemptions must therefore match past leading
# repo-selection flags, or the stack recommends a form it then blocks — and
# with `cd … &&` also blocked by the compound check, submodule commits had no
# unblocked path at all.
echo ""
echo "--- Git global-flag normalization (expect same verdict as unprefixed form) ---"

_assert_exit "git -C <path> status exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/api status"}}'

_assert_exit "git -C <path> commit exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/api commit -m wip"}}'

_assert_exit "git -C <path> rev-parse exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/api rev-parse HEAD"}}'

_assert_exit "git -C <path> log --oneline -N exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/api log --oneline -5"}}'

_assert_exit "git --git-dir=<p> --work-tree=<p> status exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git --git-dir=/r/.git --work-tree=/r status"}}'

_assert_exit "git --no-pager status exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git --no-pager status"}}'

# Normalization must not manufacture exemptions the bare form never had.
_assert_exit "git -C <path> bare log still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/api log"}}'

_assert_exit "git -C <path> diff (unbounded) still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/api diff"}}'

# `-c` is NOT peeled: it can carry arbitrary aliases, so it must fall through.
_assert_exit "git -c alias injection still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git -c alias.x=!id x"}}'

# Compound detection still runs on the full command, before normalization.
_assert_exit "git -C <path> status && cat blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/api status && cat /etc/passwd"}}'

# Flag with no subcommand after it must not be treated as exempt.
_assert_exit "git -C <path> alone blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/api"}}'

# --- Version-flag disambiguation (-v/-V overloaded with "verbose") ---
echo ""
echo "--- Version-flag disambiguation (bare version query exempt; verbose test runs blocked) ---"

# Unambiguous long form --version is always exempt (bounded output).
_assert_exit "node --version exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"node --version"}}'
_assert_exit "pytest --version exempt (long form is unambiguous)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"pytest --version"}}'

# Bare two-token -v/-V version query on a non-runner: exempt.
_assert_exit "node -v exempt (bare version query)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"node -v"}}'
_assert_exit "python -V exempt (bare version query)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"python -V"}}'

# Verbose test runs must be BLOCKED (the bug this fixes): a runner with -v, and
# any -v that is not the sole argument.
_assert_exit "pytest -v blocked (verbose, not a version query)" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"pytest -v"}}'
_assert_exit "pytest tests/ -v blocked (>2 tokens)" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"pytest tests/ -v"}}'
_assert_exit "prove -v blocked (verbose test run)" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"prove -v"}}'
_assert_exit "cargo test -v blocked (>2 tokens)" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cargo test -v"}}'
_assert_exit "make test -v blocked (>2 tokens)" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"make test -v"}}'
_assert_exit "some_tool --config x -v blocked (>2 tokens)" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"foo --config x -v"}}'

# --- Allowlist: previously-unblocked commands now blocked (expect exit 2) ---
echo ""
echo "--- Allowlist: previously-unblocked commands now blocked (expect exit 2) ---"

_assert_exit "cat command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}'

_assert_exit "find command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.sh\""}}'

_assert_exit "grep command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"grep -r TODO src/"}}'

_assert_exit "curl command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'

_assert_exit "node command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"node -e \"console.log(1)\""}}'

_assert_exit "python3 command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"python3 script.py"}}'

_assert_exit "sed command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"sed -i s/foo/bar/ file.txt"}}'

# --- VBW/planning exempt tests (expect exit 0) ---
echo ""
echo "--- VBW/planning exempt tests (expect exit 0) ---"

_assert_exit "vbw planning script exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"bash /Users/dev/project/.vbw-planning/scripts/resolve.sh"}}'

_assert_exit "vbw plugin root link exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"bash /tmp/.vbw-plugin-root-link-abc123/scripts/run.sh"}}'

# --- Version query exempt tests (expect exit 0) ---
echo ""
echo "--- Version query exempt tests (expect exit 0) ---"

_assert_exit "version flag exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"node --version"}}'

# --- Git log/diff exempt tests (expect exit 0) ---
echo ""
echo "--- Git log/diff exempt tests (expect exit 0) ---"

_assert_exit "git log --oneline exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git log --oneline -10"}}'

_assert_exit "git diff --stat exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git diff --stat"}}'

# --- 47-02: bare git log/diff/show now blocked (expect exit 2) ---
echo ""
echo "--- 47-02: bare git log/diff/show blocked (expect exit 2) ---"

_assert_exit "bare git log blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git log"}}'

_assert_exit "git log with numeric flag blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git log -20"}}'

_assert_exit "git diff with ref blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git diff HEAD~3"}}'

_assert_exit "git show with sha blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git show abc123"}}'

_assert_exit "echo command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'

_assert_exit "printf command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"printf %s\\n foo"}}'

# --- 47-02: new bounded git variants exempt (expect exit 0) ---
echo ""
echo "--- 47-02: bounded git variants exempt (expect exit 0) ---"

_assert_exit "git log --name-only exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git log --name-only -5"}}'

_assert_exit "git log --stat exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git log --stat -10"}}'

_assert_exit "git show --name-only exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git show --name-only HEAD"}}'

# --- Bypass marker test (expect exit 0 even for blocked command) ---
echo ""
echo "--- Bypass marker tests (expect exit 0) ---"

_assert_exit "ctx-exempt marker bypasses npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test # ctx-exempt"}}'

# --- Missing Context Mode sentinel test (expect exit 0) ---
echo ""
echo "--- Missing sentinel tests (expect exit 0, deadlock prevention) ---"

# Remove sentinel to simulate Context Mode not yet initialized
rm -f "$CM_SENTINEL"

_assert_exit "missing sentinel allows npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

# Restore sentinel for remaining tests
touch "$CM_SENTINEL"

# --- Context Mode not installed test (expect exit 0) ---
echo ""
echo "--- Context Mode not installed test (expect exit 0) ---"

# Write "0" to cache to simulate Context Mode not detected
echo "0" > "$CM_CACHE"

_assert_exit "no CM install allows npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

# Restore cache for any subsequent tests
echo "1" > "$CM_CACHE"

# --- Fail-open tests (expect exit 0) ---
echo ""
echo "--- Fail-open tests (empty/malformed JSON, expect exit 0) ---"

_assert_exit "empty JSON fail-open" 0 \
    '{}'

_assert_exit "malformed JSON fail-open" 0 \
    'not-json'

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
