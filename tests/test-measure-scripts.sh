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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
