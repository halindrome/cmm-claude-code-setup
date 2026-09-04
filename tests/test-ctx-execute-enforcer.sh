#!/bin/bash
# test-ctx-execute-enforcer.sh — Tests for ctx-execute-enforcer.sh large-output blocking
# Usage: bash tests/test-ctx-execute-enforcer.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC_HOOK="$SCRIPT_DIR/../hooks/project/ctx-execute-enforcer.sh"

PASS=0; FAIL=0
_assert_exit() {
    local label="$1" expected="$2" json="$3"
    local actual=0
    # cwd must be the isolated fake repo: the hook derives PROJECT_ROOT from
    # `git rev-parse --show-toplevel` at the cwd, and that is what keeps this
    # suite off the real session's sentinel. See the setup block below.
    echo "$json" | (cd "$FAKE_PROJ" && bash "$HOOK") >/dev/null 2>&1 || actual=$?
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL+1))
    fi
}

# --- Sentinel simulation setup (isolated fake repo) ---
# This suite USED TO drive the hook against the REAL project hash, so $CM_CACHE
# and $CM_SENTINEL were the same files a live Claude Code session in this repo
# is using. That was a race, not just an inconvenience: the four assertions
# below that require the sentinel absent / "ready" / empty / stale are destroyed
# whenever context-mode-sentinel-writer.sh refreshes it to "live" mid-run (it
# fires on every ctx_* PostToolUse). The suite then reported a pass or a failure
# depending on timing, so a green run proved nothing.
#
# Fix: give the hook its own git repo to resolve. The hook takes PROJECT_ROOT
# from `git rev-parse --show-toplevel` at the cwd and checks it against its own
# location (path-integrity check), so the hook is copied into the fake repo at
# the same relative layout — the pattern tests/test-agent-hook-enforcement.sh
# already uses. Nothing here touches the real session's sentinel.
if [ ! -f "$SRC_HOOK" ]; then
    echo ""
    echo "NOTE: $SRC_HOOK does not exist yet."
    echo "This test suite is complete but requires Plan 32-01 to be merged first."
    echo "Run again after hooks/project/ctx-execute-enforcer.sh is created."
    echo ""
    echo "Results: $PASS passed, $FAIL failed (hook not yet available)"
    exit 0
fi

FAKE_ROOT="$(mktemp -d)"
FAKE_PROJ="$(cd "$FAKE_ROOT" && pwd -P)/proj"
mkdir -p "$FAKE_PROJ/hooks/project" "$FAKE_PROJ/hooks/lib"
git -C "$FAKE_PROJ" init -q
cp "$SRC_HOOK" "$FAKE_PROJ/hooks/project/ctx-execute-enforcer.sh"
cp "$SCRIPT_DIR/../hooks/lib/"*.sh "$FAKE_PROJ/hooks/lib/" 2>/dev/null || true
HOOK="$FAKE_PROJ/hooks/project/ctx-execute-enforcer.sh"

# Resolve the hash the same way the hook will, from inside the fake repo.
FAKE_ROOT_CANON="$(cd "$FAKE_PROJ" && git rev-parse --show-toplevel 2>/dev/null || echo "$FAKE_PROJ")"
if command -v md5 >/dev/null 2>&1; then
    PROJECT_HASH="$(echo "$FAKE_ROOT_CANON" | md5 -q)"
else
    PROJECT_HASH="$(echo "$FAKE_ROOT_CANON" | md5sum | awk '{print $1}')"
fi

CM_CACHE="/tmp/ctx-enforcer-${PROJECT_HASH}"
CM_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"

_cleanup_fake() {
    rm -rf "$FAKE_ROOT"
    rm -f "$CM_CACHE" "$CM_SENTINEL"
    rm -f "/tmp/cmm-project-root-$(echo "$FAKE_PROJ" | md5 -q 2>/dev/null || echo "$FAKE_PROJ" | md5sum | awk '{print $1}')"
}
trap _cleanup_fake EXIT

# Create sentinels to simulate Context Mode installed and PROVEN LIVE.
# "live" (not a bare touch) is required: the enforcer arms only on a sentinel
# whose content is "live" — written by context-mode-sentinel-writer.sh after a
# real ctx_* call — and only while that file is fresh.
echo "1" > "$CM_CACHE"
echo "live" > "$CM_SENTINEL"

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

# --- Liveness regression tests ---
# Both cases below reproduce the 2026-08-05 incident: Claude Code re-extracted the
# plugin cache while a session was starting, so installPath existed (cache says
# "1", detect_context_mode says installed) but the MCP server never registered and
# no ctx_* tool existed. The enforcer must NOT mandate tools it has not seen work.
echo ""
echo "--- Sentinel liveness tests (expect exit 0, dead-server fail-open) ---"

# "ready" = cmm-session-start.sh's optimistic on-disk verdict, never confirmed by
# a real ctx_* call. This is the exact state that wedged the session for 24 min.
echo "ready" > "$CM_SENTINEL"
_assert_exit "unconfirmed 'ready' sentinel allows npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

# A bare touch (empty file) is not a liveness verdict either.
: > "$CM_SENTINEL"
_assert_exit "empty sentinel allows npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

# "live" but stale — the server answered once, then died mid-session. Enforcement
# must lift on its own rather than wedging until restart.
echo "live" > "$CM_SENTINEL"
touch -t "$(date -v-2H '+%Y%m%d%H%M' 2>/dev/null || date -d '2 hours ago' '+%Y%m%d%H%M')" "$CM_SENTINEL"
_assert_exit "stale 'live' sentinel allows npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

# Fresh "live" re-arms enforcement — the positive control for the three above.
echo "live" > "$CM_SENTINEL"
_assert_exit "fresh 'live' sentinel still blocks npm test" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

# Restore sentinel for remaining tests
echo "live" > "$CM_SENTINEL"

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

# --- Laundering guard: the suggested replacement must not carry a truncation ---
# Measured 2026-09-03: of 1,501 blocked Bash calls that escalated into a ctx_*
# call, 252 carried the identical `| head -N` into the sandbox, where nothing
# inspected it. Suggesting a payload that ctx-payload-guard will immediately
# block is two blocks for one intent -- friction with no conversion.
echo ""
echo "--- Suggested ctx_execute replacement strips output truncation ---"

_err_of() { echo "$1" | (cd "$FAKE_PROJ" && bash "$HOOK") 2>&1 >/dev/null || true; }

_OUT=$(_err_of '{"tool_name":"Bash","tool_input":{"command":"orb list 2>&1 | head -20"}}')
if printf '%s' "$_OUT" | grep -F 'ctx_execute(' | grep -qF '| head'; then
    echo "FAIL: suggested replacement still contains the truncating pipe"
    FAIL=$((FAIL+1))
else
    echo "PASS: suggested replacement strips the truncating pipe"
    PASS=$((PASS+1))
fi
if printf '%s' "$_OUT" | grep -qF 'code="orb list 2>&1"'; then
    echo "PASS: suggested replacement names the stripped command concretely"
    PASS=$((PASS+1))
else
    echo "FAIL: suggested replacement is a bare placeholder (agent will refill it)"
    FAIL=$((FAIL+1))
fi
if printf '%s' "$_OUT" | grep -qF 'intent='; then
    echo "PASS: suggested replacement offers intent="
    PASS=$((PASS+1))
else
    echo "FAIL: suggested replacement omits intent="
    FAIL=$((FAIL+1))
fi
# QA round 1, F-02: a stdout redirect echoed verbatim hands the agent a payload
# that ctx-payload-guard then hard-blocks -- two blocks for one intent, with this
# hook authoring the second. Only fd 1 is stripped.
_OUTR=$(_err_of '{"tool_name":"Bash","tool_input":{"command":"git log --oneline > /tmp/log.txt && wc -l /tmp/log.txt"}}')
if printf '%s' "$_OUTR" | grep -F 'ctx_execute(' | grep -qF '> /tmp/log.txt'; then
    echo "FAIL: suggested replacement still redirects stdout to a file"
    FAIL=$((FAIL+1))
else
    echo "PASS: suggested replacement strips the stdout redirect"
    PASS=$((PASS+1))
fi
# Stream splitting and discards are things the guard ALLOWS, so stripping them
# here would corrupt a command it was never going to object to.
_OUTE=$(_err_of '{"tool_name":"Bash","tool_input":{"command":"make test 2> err.log && echo ok"}}')
if printf '%s' "$_OUTE" | grep -qF '2> err.log'; then
    echo "PASS: stderr redirect is preserved in the suggestion"
    PASS=$((PASS+1))
else
    echo "FAIL: stderr redirect was stripped (the guard never blocks it)"
    FAIL=$((FAIL+1))
fi
_OUTD=$(_err_of '{"tool_name":"Bash","tool_input":{"command":"noisy-cmd > /dev/null && echo ok"}}')
if printf '%s' "$_OUTD" | grep -qF '> /dev/null'; then
    echo "PASS: /dev/null discard is preserved in the suggestion"
    PASS=$((PASS+1))
else
    echo "FAIL: /dev/null discard was stripped (the guard never blocks it)"
    FAIL=$((FAIL+1))
fi

# A compound with no truncation must keep its command intact.
_OUT2=$(_err_of '{"tool_name":"Bash","tool_input":{"command":"make test && echo done"}}')
if printf '%s' "$_OUT2" | grep -qF 'code="make test && echo done"'; then
    echo "PASS: non-truncating compound is echoed unchanged"
    PASS=$((PASS+1))
else
    echo "FAIL: non-truncating compound was altered"
    FAIL=$((FAIL+1))
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
