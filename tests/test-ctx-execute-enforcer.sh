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

# Parse the hook before asserting anything about its behaviour. A bash syntax
# error exits 2 -- which is this hook's BLOCK code -- so a malformed hook keeps
# every "expect exit 2" assertion green and only breaks the exemptions after the
# bad line. Observed 2026-09-04: an unescaped `>` in a case pattern (it is a
# metacharacter there) took out 18 exemptions while the suite still reported 97
# passes. Fail loudly and first instead.
if bash -n "$HOOK" 2>/dev/null; then
    echo "PASS: hook parses (bash -n)"
    PASS=$((PASS+1))
else
    echo "FAIL: hook has a SYNTAX ERROR — every exit-2 assertion below is meaningless"
    bash -n "$HOOK" 2>&1 | sed 's/^/    /'
    FAIL=$((FAIL+1))
fi

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

# NOTE: `sed -i` moved from blocked to EXEMPT. An in-place edit writes to a file
# and prints nothing, so there is no output to sandbox — it is the same category
# as the mv/cp exemptions, and it matches upstream context-mode's own rule for
# curl/wget ("allow silent file-output downloads, block stdout floods", #166).
# The pair below is the point: the `-i` is what makes it silent, and one flag
# apart the verdict must invert.
_assert_exit "sed -i (in-place, silent) exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"sed -i s/foo/bar/ file.txt"}}'

_assert_exit "sed WITHOUT -i (floods stdout) still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"sed s/foo/bar/ big.c"}}'

# --- In-place editors exempt (expect exit 0) ---
echo ""
echo "--- In-place editors exempt (expect exit 0) ---"

_assert_exit "sed -i '' (BSD/macOS form) exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"sed -i '\''back'\'' s/a/b/ f.ts"}}'

_assert_exit "sed -i.bak (GNU suffix form) exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"sed -i.bak s/a/b/ f.ts"}}'

_assert_exit "perl -0pi -e exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"perl -0pi -e s/a/b/ f.pl"}}'

_assert_exit "perl -pe WITHOUT -i (prints) still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"perl -pe s/a/b/ big.c"}}'

_assert_exit "awk -i inplace exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"awk -i inplace {print} f.txt"}}'

# QA round 1 F-03: an `i` inside a -M module / -r library name is not -i.
_assert_exit "perl -pi.bak -e exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"perl -pi.bak -e s/a/b/ f.pl"}}'
_assert_exit "perl -pie (cluster) exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"perl -pie s/a/b/ f.pl"}}'
_assert_exit "perl -MFile::Find -e (prints) blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"perl -MFile::Find -e find(sub{print},q(.))"}}'
_assert_exit "perl -Mwarnings -e (prints) blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"perl -Mwarnings -e print"}}'
_assert_exit "ruby -ropen-uri -e (prints) blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"ruby -ropen-uri -e puts(1)"}}'
_assert_exit "ruby -pi -e exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"ruby -pi -e gsub(/a/,%q(b)) f.rb"}}'
# F-04: a <<'Z' inside a quoted argument is not a heredoc.
_assert_exit "quoted <<'Z' cannot hide the next line" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x <<'"'"'Z'"'"'\"\nnpm test"}}'
_assert_exit "quoted <<'Z' in a cd path cannot hide the next line" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cd \"/tmp<<'"'"'Z'"'"'\"\nnpm test"}}'

# --- run_in_background exempt (expect exit 0) ---
# Output goes to a background task, never into the conversation, so sandboxing
# buys nothing. No hook in this stack read this field before 2026-09-04.
echo ""
echo "--- run_in_background exempt (expect exit 0) ---"

_assert_exit "run_in_background=true exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npx ng serve --port 4200","run_in_background":true}}'

_assert_exit "run_in_background=false still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npx ng serve --port 4200","run_in_background":false}}'

_assert_exit "run_in_background absent still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npx ng serve --port 4200"}}'

# --- Quoted here-doc bodies are blanked before the compound scan ---
# `git commit -F - <<'EOF' … EOF` is a git-write (already exempt) that prints two
# lines, but the heredoc's newlines tripped the compound check, so committing
# with a message body was blocked outright. Only QUOTED heredocs are blanked:
# an unquoted <<W expands parameters and command substitutions, so its body is
# live code and must stay visible to the scan. That split is the whole point.
echo ""
echo "--- Quoted here-doc exemption (expect exit 0) ---"

_assert_exit "git commit -F - with quoted heredoc allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<'"'"'EOF'"'"'\nfix: a subject\n\nbody with ; and && and | inside\nEOF"}}'

_assert_exit "git -C <dir> commit with quoted heredoc allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git -C apps/mobile commit -F - <<'"'"'EOF'"'"'\nfix: subject\nEOF"}}'

_assert_exit "double-quoted heredoc terminator allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<\"EOF\"\nfix: subject\nEOF"}}'

_assert_exit "<<- dash form allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<-'"'"'EOF'"'"'\nfix: subject\nEOF"}}'

echo ""
echo "--- Here-doc exemption must NOT widen (expect exit 2) ---"

# Unquoted heredoc: body expands, $(...) is live code.
_assert_exit "UNQUOTED heredoc still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<EOF\nsubject\nEOF"}}'

# Anything after the terminator survives the blanking.
_assert_exit "operator after heredoc terminator still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<'"'"'EOF'"'"'\nsubject\nEOF\n; rm -rf /tmp/x"}}'

_assert_exit "&& after heredoc terminator still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<'"'"'EOF'"'"'\nsubject\nEOF\n&& npm test"}}'

# The heredoc does not make a non-exempt command exempt.
_assert_exit "non-exempt command with heredoc still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat <<'"'"'EOF'"'"'\nlots of output\nEOF"}}'

# --- Leading variable assignment peels like a leading `cd` (expect exit 0) ---
# Observed live 2026-09-04, immediately after cwd-guard.sh blocked the `cd` form
# and told the agent to use `git -C`:
#   M=/Users/…/apps/mobile; git -C $M merge origin/ic3_13_patches
# `git merge` is exempt and the `-C` normalization exists to make `git -C <path>
# merge` work, but the `;` after the assignment tripped the operator scan, which
# runs first — so that fix was never reached. The two gates were pushing the
# agent into each other.
echo ""
echo "--- Leading VAR= assignment peels (expect exit 0) ---"

_assert_exit "VAR= then git -C merge exempt (the observed case)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"M=/Users/ahby/Sources/lc/apps/mobile; git -C $M merge origin/ic3_13_patches"}}'

_assert_exit "VAR= with && separator exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"D=$HOME/src && git status"}}'

_assert_exit "VAR= composes with a leading cd" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && M=y; git commit -m wip"}}'

echo ""
echo "--- VAR= peel must NOT widen (expect exit 2) ---"

# A command substitution in the VALUE is live code and must never peel.
_assert_exit "VAR=\$(...) still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"M=$(cat secrets.txt); git -C $M merge x"}}'

# Peeling removes ONLY the assignment; a second separator still shows.
_assert_exit "VAR= with two more commands still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"M=x; npm test; echo done"}}'

# The peel is not an exemption: what is left must still earn its own pass.
_assert_exit "VAR= then a non-exempt command still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"M=x; npm test"}}'

# A pipe in the value would smuggle a second command past the scan.
_assert_exit "VAR= with a pipe in the value still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"M=a|tee /tmp/x; git status"}}'

# --- File authoring exempt (expect exit 0) ---
# A literal-emitting command redirected to a file writes bytes to the file, not
# to stdout, so there is nothing to sandbox. The block was not merely friction:
# it routed the command to ctx_execute, whose subprocess filesystem is discarded,
# so the suggested replacement did not write the file at all.
echo ""
echo "--- File authoring exempt (expect exit 0) ---"

_assert_exit "cat > file with quoted heredoc exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"cat > notes.md <<'"'"'EOF'"'"'\nsome literal text\nEOF"}}'

_assert_exit "echo > file exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"echo hello > f.txt"}}'

_assert_exit "printf >> file exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"printf %s x >> f.txt"}}'

_assert_exit "cat file > file (silent copy) exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"cat a.txt > b.txt"}}'

echo ""
echo "--- Authoring exemption must NOT widen (expect exit 2) ---"

# The `>` must be REAL. Quoted spans are scrubbed from _OPCHECK, so a redirect
# inside a string does not buy the exemption and bare echo stays blocked (47-02).
_assert_exit "echo with a quoted > still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"echo \"a > b\""}}'

_assert_exit "bare echo still blocked (47-02)" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'

# A redirect does not make an arbitrary command silent.
_assert_exit "curl > file still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com > page.html"}}'

# cat WITHOUT a redirect floods stdout — the case this hook exists for.
_assert_exit "cat without a redirect still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat big.c"}}'

# A STDERR redirect is not authoring: stdout still floods. A case glob cannot see
# the fd digit, so `cat big.c 2>/dev/null` matched as "cat " + "big.c 2" + ">" +
# "/dev/null" and was exempted — the exact hole this hook exists to close, on one
# of the most common idioms an agent writes.
_assert_exit "cat with 2>/dev/null still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat big.c 2>/dev/null"}}'

_assert_exit "cat with 2>err.log still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat src/huge.py 2>err.log"}}'

_assert_exit "echo with only a stderr redirect still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"echo hello 2>/dev/null"}}'

# ...but a real stdout redirect alongside a stderr one is still authoring.
_assert_exit "echo > file with 2>/dev/null still exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"echo hello > f.txt 2>/dev/null"}}'

# QA round 1 F-07: a terminal stream is not a file.
_assert_exit "cat > /dev/stdout blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat big.c > /dev/stdout"}}'
_assert_exit "cat > /dev/stderr blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat big.c >/dev/stderr"}}'

# An UNQUOTED heredoc keeps its body and newlines visible to the compound scan,
# so it is blocked before it can reach the authoring case. Fail-closed.
_assert_exit "cat > file with UNQUOTED heredoc still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat > f.sh <<EOF\n$(rm -rf /tmp/x)\nEOF"}}'

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
# QA round 2: this hook must NOT strip stdout redirects. Doing so (tried in
# b9cc572 for round-1 F-02) requires the guard's AUTHORING and read-back-later
# exemptions to decide whether a redirect is objectionable at all; without them
# the strip deleted legitimate file writes and the paired read then saw a stale
# or absent file — a corrupted command the agent is explicitly told to paste.
# The redirect double-block stands instead: blocked here, moved into ctx_execute
# unchanged, and the guard's own message names the `2>&1 | tee` fix. Two
# round-trips, converging.
# Scope the grep to the ctx_execute( line: the block message unconditionally
# echoes the original command under "Detected:", so a whole-stderr grep finds the
# redirect no matter what _SUGGEST holds and pins nothing. The payload also needs
# a real truncation, or _SUGGEST == _ORIG_COMMAND and the branch under test is
# never entered at all.
_OUTR=$(_err_of '{"tool_name":"Bash","tool_input":{"command":"jq -r .name pkg.json > /tmp/n.txt && cat /tmp/n.txt | head -5"}}')
if printf '%s' "$_OUTR" | grep -F 'ctx_execute(' | grep -qF '> /tmp/n.txt'; then
    echo "PASS: file write is preserved in the suggestion (not silently dropped)"
    PASS=$((PASS+1))
else
    echo "FAIL: suggestion dropped the file write; the paired read would break"
    FAIL=$((FAIL+1))
fi
if printf '%s' "$_OUTR" | grep -F 'ctx_execute(' | grep -qF '| head'; then
    echo "FAIL: suggestion kept the truncating pipe"
    FAIL=$((FAIL+1))
else
    echo "PASS: suggestion still strips the truncating pipe"
    PASS=$((PASS+1))
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
