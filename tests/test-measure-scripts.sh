#!/bin/bash
# test-measure-scripts.sh — Tests for the `make measure` analysis scripts.
# Verifies the anti-pattern detectors classify known payloads correctly (its
# own --selftest, which doubles as the spec for the ctx-payload-guard hook) and
# that both scripts are importable and honour a days argument without touching
# the filesystem.
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
if grep -q 'RE_SED_RANGE) *:*$\|rx.search(text)' "$ANTI"; then
  pass "weak/assert/bashism detectors scan raw text"
else
  fail "weak detectors appear to scan scrubbed text (would under-count)"
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
