#!/bin/bash
# test-vbw2-measure.sh — make measure reports VBW 2 workflow agents (R1)
# scripts/analyze-enforcement.py must read workflow subagent transcripts
# (projects/<slug>/<session>/subagents/workflows/<wf>/agent-*.jsonl, agent type
# from the sibling agent-*.meta.json), count a Bash call that runs the
# cmm-query.sh wrapper or `codebase-memory-mcp cli <tool>` as a CMM call of
# that tool, report per run and agent type in a "VBW 2 WORKFLOW AGENTS" section,
# and keep vbw:* runs out of the bypass scoring (sections 5 and 7). Fixture:
# tests/fixtures/vbw2-workflow (fixed timestamps 2026-10-01).
#
# Row contract: one line per (project, run, agent type) after the section
# header, holding the project slug, the run id, the agent type and
# CMM=<n> Read=<n> Grep=<n> Glob=<n> Bash=<n>, plus <cmm_tool>=<n> per CMM tool.
# Usage: bash tests/test-vbw2-measure.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENF="$REPO/scripts/analyze-enforcement.py"
FIX="$SCRIPT_DIR/fixtures/vbw2-workflow/projects"

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

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# Copy the fixture into a scratch HOME so file mtimes are fresh (the script also
# filters files by mtime); record timestamps stay 2026-10-01.
mkdir -p "$T/a/.config/claude-code" "$T/b/.config/claude-code/projects/-fixture-proj"
cp -R "$FIX" "$T/a/.config/claude-code/projects"
cp "$FIX/-fixture-proj/s1.jsonl" "$T/b/.config/claude-code/projects/-fixture-proj/"

_run() { # <home> <args...> -> OUT, RC
    local h="$1"
    shift
    RC=0
    OUT="$(HOME="$h" python3 "$ENF" "$@" 2>&1)" || RC=$?
}
# _row <run> <agent_type> -> the VBW 2 section row for that run and agent type
_row() {
    printf '%s\n' "$OUT" | python3 -c '
import re, sys
run, at = sys.argv[1], sys.argv[2]
lines = sys.stdin.read().splitlines()
start = next((i for i, l in enumerate(lines) if "VBW 2 WORKFLOW AGENTS" in l), None)
if start is None:
    raise SystemExit
for l in lines[start + 1:]:
    if re.match(r"^\s*[0-9]+[a-z]?\. ", l):
        break
    if "-fixture-proj" in l and run in l and re.search(r"(^|\s)" + re.escape(at) + r"(\s|$)", l):
        print(l)
        break' "$1" "$2"
}
# _has <row> <k=v>...: every token present exactly
_has() {
    local row="$1"
    shift
    ROW="$row" python3 -c '
import os, re, sys
toks = dict(re.findall(r"(?<![\w-])([A-Za-z_]+)=(\d+)", os.environ["ROW"]))
sys.exit(0 if all(toks.get(k) == v for k, v in (a.split("=") for a in sys.argv[1:])) else 1)' "$@"
}

_run "$T/a" 36500
if [ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q Traceback; then
    _pass "runs over the fixture (malformed line, empty file) without crashing"
else
    _fail "crashed on the fixture (rc=$RC): $(printf '%s' "$OUT" | tail -3)"
fi
if printf '%s' "$OUT" | grep -q 'VBW 2 WORKFLOW AGENTS'; then _pass "VBW 2 WORKFLOW AGENTS section present"; else _fail "no VBW 2 WORKFLOW AGENTS section"; fi

ROW="$(_row wf_fix-build vbw:dev)"
if [ -n "$ROW" ] && _has "$ROW" CMM=3 Read=2 Grep=1 Glob=1 Bash=1; then
    _pass "wf_fix-build vbw:dev: CMM=3 Read=2 Grep=1 Glob=1 Bash=1"
else
    _fail "wf_fix-build vbw:dev counts wrong: '$ROW'"
fi
if [ -n "$ROW" ] && _has "$ROW" search_graph=2 trace_path=1; then
    _pass "wrapper and 'codebase-memory-mcp cli' calls attributed: search_graph=2 trace_path=1"
else
    _fail "CMM calls not attributed to their tool names: '$ROW'"
fi
ROW="$(_row wf_fix-build vbw:qa)"
if [ -n "$ROW" ] && _has "$ROW" CMM=0 Read=0 Grep=0 Glob=0 Bash=6; then
    _pass "wf_fix-build vbw:qa: CMM=0 Bash=6"
else
    _fail "wf_fix-build vbw:qa counts wrong: '$ROW'"
fi
ROW="$(_row wf_fix-map vbw:scout)"
if [ -n "$ROW" ] && _has "$ROW" CMM=2 Read=2 Grep=0 Glob=0 Bash=0 get_architecture=2; then
    _pass "wf_fix-map vbw:scout: two scouts summed, CMM=2 Read=2 get_architecture=2"
else
    _fail "wf_fix-map vbw:scout counts wrong: '$ROW'"
fi
if [ -z "$(_row wf_fix-other general-purpose)" ]; then
    _pass "non-VBW workflow agent not listed as a VBW 2 agent"
else
    _fail "general-purpose workflow agent listed in the VBW 2 section"
fi

echo "--- vbw:* runs are not scored as bypasses; other scoring unchanged ---"
if printf '%s\n' "$OUT" | grep -Eq '^workflow +transcripts with >=5 tool calls: +1 \| zero CMM: +1 '; then
    _pass "section 7: workflow tier counts only the non-VBW agent"
else
    _fail "section 7 workflow row still counts vbw:* runs: $(printf '%s\n' "$OUT" | grep -E '^workflow +transcripts' || echo none)"
fi
if printf '%s\n' "$OUT" | grep -Eq '^main +transcripts with >=5 tool calls: +1 \| zero CMM: +1 '; then
    _pass "section 7: main tier unchanged"
else
    _fail "section 7 main row changed"
fi
if printf '%s\n' "$OUT" | grep -Eq '^workflow +5 +0 +0 +5 '; then
    _pass "section 5: workflow adoption counts only the non-VBW agent's 5 calls"
else
    _fail "section 5 workflow row still includes vbw:* runs: $(printf '%s\n' "$OUT" | grep -E '^workflow +[0-9]+ +[0-9]+ ' || echo none)"
fi

if printf '%s\n' "$OUT" | grep -Eq '^workflow +6 +2 +33\.3%'; then
    _pass "section 1: a hook-reached vbw:* run counts as reached (workflow 2/6)"
else
    _fail "section 1 REACH drops hook-reached vbw:* runs: $(printf '%s\n' "$OUT" | grep -E '^workflow +[0-9]+ +[0-9]+ +[0-9.]+%' || echo none)"
fi

echo "--- quoted wrapper path (project root with a space) counts as CMM ---"
if ENF="$ENF" python3 -c '
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("enf", os.environ["ENF"]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
r = m.CMM_BASH_RE.search("bash '"'"'/My Proj/.claude/hooks/cmm-query.sh'"'"' search_graph '"'"'{}'"'"'")
sys.exit(0 if r and r.group(1) == "search_graph" else 1)'; then
    _pass "quoted cmm-query.sh path attributed to search_graph"
else
    _fail "quoted cmm-query.sh path not counted as a CMM call"
fi

echo "--- DAYS and MODEL filters apply to workflow transcripts ---"
_run "$T/a" 1
if [ "$RC" = 0 ] && [ -z "$(_row wf_fix-build vbw:dev)" ] && [ -z "$(_row wf_fix-map vbw:scout)" ]; then
    _pass "DAYS=1 drops the 2026-10-01 workflow records"
else
    _fail "DAYS=1 still reports the fixture runs"
fi
_run "$T/a" 36500 --model other-model
if [ "$RC" = 0 ] && [ -z "$(_row wf_fix-build vbw:dev)" ]; then
    _pass "--model other-model drops the fixture's workflow tool calls"
else
    _fail "--model other-model still counts them"
fi
_run "$T/a" 36500 --model claude-test-model
ROW="$(_row wf_fix-build vbw:dev)"
if [ -n "$ROW" ] && _has "$ROW" CMM=3; then
    _pass "--model claude-test-model keeps them"
else
    _fail "--model claude-test-model lost them: '$ROW'"
fi

echo "--- no workflows directory ---"
_run "$T/b" 36500
if [ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q Traceback; then
    _pass "a corpus without subagents/workflows runs cleanly"
else
    _fail "crashed without a workflows dir (rc=$RC)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
