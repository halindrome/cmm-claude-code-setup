#!/bin/bash
# test-measure-scripts.sh — Tests for the `make measure` analysis scripts.
#
# Scope, stated accurately: this file drives the scripts' own --selftest (whose
# rows are the spec for the STRONG, WEAK, assert and bashism detectors, and
# double as the spec for the ctx-payload-guard hook), asserts that the WEAK side
# is exercised at all, and checks that both scripts are importable, honour a
# days argument, and never write to the filesystem.
#
# What it does NOT do, so nobody reads more into a green run: it does not run
# the two mirrored detectors against each other. `analyze-antipatterns.py` and
# `hooks/project/ctx-payload-guard.sh` carry deliberately parallel logic and can
# drift while both suites stay green. They agree on every SELFTEST row today.
# Usage: bash tests/test-measure-scripts.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ANTI="$ROOT/scripts/analyze-antipatterns.py"
ENF="$ROOT/scripts/analyze-enforcement.py"

PASS=0; FAIL=0
pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== measure scripts ==="
echo ""
echo "--- both scripts present and syntactically valid ---"
for f in "$ANTI" "$ENF"; do
  b="$(basename "$f")"
  if [ -f "$f" ]; then pass "$b present"; else fail "$b missing"; continue; fi
  # ast.parse, not py_compile: py_compile writes a __pycache__/ dir into the repo.
  if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null; then
    pass "$b parses"
  else
    fail "$b has a syntax error"
  fi
done

echo ""
echo "--- anti-pattern detector selftest (spec for ctx-payload-guard) ---"
# The selftest asserts every BLOCK case fires and every legitimate PASS case
# does not: tee, bare head/tail, stderr redirects, /dev/null, reused targets,
# command substitution, heredoc authoring, and non-shell languages.
if out="$(python3 "$ANTI" --selftest 2>&1)"; then
  pass "detector selftest: 0 failures"
else
  fail "detector selftest reported failures"
  printf '%s\n' "$out" | grep '^FAIL' || true
fi

echo ""
echo "--- selftest covers the stream-splitting rule ---"
# Only stdout leaving the pipeline defeats capture. Redirecting or discarding
# stderr must never be flagged, and `1> file` must be, despite the fd digit.
for probe in "cmd 2> err.log" "cmd 2>/dev/null" "cmd 2>&1" "echo hi >&2" "cmd 1> out.log"; do
  if grep -qF -- "$probe" "$ANTI"; then
    pass "selftest pins: $probe"
  else
    fail "selftest missing stream case: $probe"
  fi
done

echo ""
echo "--- weak detectors run on raw text, not the scrubbed copy ---"
# Regression guard: scrubbing quoted spans before the weak scan blanks the very
# argument being detected (`sed -n '1,3p'`), which silently zeroed the weak
# counts and would have made a migration from head/tail look like a win.
#
# This used to be a grep for a source pattern, and it was VACUOUS: one of its
# two alternatives (`rx.search(text)`) also matches the bashism comprehension,
# so it passed unconditionally — including against a copy with the fix removed.
# Behaviour is the thing to assert, so assert behaviour: a line-range whose
# argument is quoted must still be detected. That is exactly what scrubbing
# first would destroy.
_WEAKPROBE=$(python3 - "$ANTI" <<'PY' 2>/dev/null
import importlib.util, sys
sp = importlib.util.spec_from_file_location("a", sys.argv[1])
m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
print(",".join(m.classify("sed -n '1,60p' run.log", "shell")["weak"]))
PY
)
if [ "$_WEAKPROBE" = "sed line-range" ]; then
  pass "quoted line-range is still detected (weak scan sees raw text)"
else
  fail "weak scan missed a quoted line-range (got: '${_WEAKPROBE}')"
fi

echo ""
echo "--- the WEAK side has an executable spec at all ---"
# The migration reading depends on WEAK being measured. Every SELFTEST row used
# to assert only `strong`, so the three weak detectors were unexercised: one
# could stop matching and a fall in STRONG would read as a win rather than as
# agents moving to `sed -n '1,60p'`.
for _sym in WEAK_SELFTEST ASSERT_SELFTEST; do
  if grep -q "^${_sym} = \[" "$ANTI"; then
    pass "$_sym exists"
  else
    fail "$_sym missing — the weak/assert detectors have no spec"
  fi
done
# Capture first, then grep. Piping into `grep -q` under `set -o pipefail` makes
# grep exit at the first match, python3 take SIGPIPE, and the pipeline return
# 141 — the same latent race that was flapping test-phase-66-install-scope.sh.
_SELFTEST_OUT=$(python3 "$ANTI" --selftest 2>&1 || true)
if printf '%s' "$_SELFTEST_OUT" | grep -q 'ok    weak='; then
  pass "selftest actually exercises the weak detectors"
else
  fail "selftest runs no weak rows"
fi
if printf '%s' "$_SELFTEST_OUT" | grep -q 'ok    assert='; then
  pass "selftest actually exercises the assert detector"
else
  fail "selftest runs no assert rows"
fi

echo ""
echo "--- scripts are read-only over the transcript corpus ---"
for f in "$ANTI" "$ENF"; do
  b="$(basename "$f")"
  if grep -qE "open\([^)]*['\"][wa]['\"]|os\.remove|shutil\.|\.write\(" "$f"; then
    fail "$b appears to write to disk"
  else
    pass "$b performs no writes"
  fi
done

echo ""
echo "--- every emitting hook has a STACK_FP fingerprint ---"
# Regression guard: ctx-payload-guard and ctx-shell-compat shipped without one,
# so `make measure` never counted their blocks. Rule: any hook that emits a
# BLOCKED message or additionalContext must contain a STACK_FP string verbatim.
# This checks hook SOURCE, not emitted text: a hook that builds its prefix from a
# variable (`echo "[${SELF}] BLOCKED"`) will fail here -- keep the prefix literal.
_FPMISS=$(python3 - "$ENF" "$ROOT"/hooks/*/*.sh <<'PY' 2>&1
import sys
src = open(sys.argv[1]).read()
ns = {}; sys.argv[1:] = sys.argv[2:]; hooks = list(sys.argv[1:]); sys.argv[1:] = []
exec(src.split("# ---------------------------------------------------------------- accumulators")[0], ns)
fps = [fp for _h, _k, fp in ns["STACK_FP"]]
for h in hooks:
    t = open(h).read()
    if ("BLOCKED" in t or "additionalContext" in t) and not any(fp in t for fp in fps):
        print(h.rsplit("/", 1)[-1])
PY
)
if [ -z "$_FPMISS" ]; then
  pass "all emitting hooks are fingerprinted"
else
  fail "hooks with no STACK_FP fingerprint: $(echo $_FPMISS)"
fi

echo ""
echo "--- --model filters tool calls by assistant message.model ---"
_FAKEHOME=$(mktemp -d)
trap 'rm -rf "$_FAKEHOME"' EXIT
mkdir -p "$_FAKEHOME/.config/claude-code/projects/p"
python3 - "$_FAKEHOME/.config/claude-code/projects/p/s.jsonl" <<'PY'
import json, sys, time
ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
def tu(model, tid, name, inp):
    return {"type": "assistant", "timestamp": ts, "message": {"model": model,
            "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}}
# A prompt-level hook: its toolUseID is synthetic (`hook-…`), never a tool_use id,
# so it belongs to no model and must survive every --model filter.
recs = [{"type": "attachment", "timestamp": ts, "attachment": {"type": "hook_additional_context",
         "toolUseID": "hook-0001", "content": "Invoke Skill('cmm-rules') now"}},
        tu("model-a", "t1", "Bash", {"command": "make test | head -5"}),
        {"type": "user", "timestamp": ts, "message": {"content": [{"type": "tool_result",
         "tool_use_id": "t1", "is_error": True, "content": "[ctx-payload-guard] BLOCKED -- x"}]}},
        tu("model-b", "t2", "Read", {"file_path": "README.md"})]
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in recs) + "\n")
PY
_A=$(HOME="$_FAKEHOME" python3 "$ENF" 1 --model model-a 2>&1 || true)
_B=$(HOME="$_FAKEHOME" python3 "$ENF" 1 --model model-b 2>&1 || true)
if printf '%s' "$_A" | grep -q 'ctx-payload-guard'; then
  pass "enforcement --model model-a counts its own block"
else
  fail "enforcement --model model-a lost the ctx-payload-guard block"
fi
if printf '%s' "$_B" | grep -q 'ctx-payload-guard'; then
  fail "enforcement --model model-b counted another model's block"
else
  pass "enforcement --model model-b excludes model-a's block"
fi
if printf '%s' "$_B" | grep -q 'skill-nudge'; then
  pass "enforcement --model keeps session-level (hook-*) emissions"
else
  fail "enforcement --model dropped a hook-* toolUseID emission"
fi
if printf '%s' "$_A" | grep -q 'model-b'; then
  pass "enforcement lists every model seen (section 9)"
else
  fail "enforcement model census missing model-b"
fi
_AA=$(HOME="$_FAKEHOME" python3 "$ANTI" 1 --model model-a 2>&1 || true)
_AB=$(HOME="$_FAKEHOME" python3 "$ANTI" 1 --model model-b 2>&1 || true)
if printf '%s' "$_AA" | grep -qE '^Bash +1 +1 '; then
  pass "antipatterns --model model-a sees its STRONG Bash payload"
else
  fail "antipatterns --model model-a missed its Bash payload"
fi
if printf '%s' "$_AB" | grep -qE '^Bash '; then
  fail "antipatterns --model model-b counted model-a's payload"
else
  pass "antipatterns --model model-b excludes model-a's payload"
fi

echo ""
echo "--- make measure target exists ---"
if grep -q '^measure:' "$ROOT/Makefile"; then
  pass "Makefile defines a measure target"
else
  fail "Makefile has no measure target"
fi
if grep -q '^DAYS ?=' "$ROOT/Makefile"; then
  pass "Makefile exposes DAYS override"
else
  fail "Makefile does not expose DAYS"
fi
if grep -q '^MODEL ?=' "$ROOT/Makefile"; then
  pass "Makefile exposes MODEL override"
else
  fail "Makefile does not expose MODEL"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
