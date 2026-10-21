#!/bin/bash
# test-phase-63-rule-refresh.sh — Regression coverage for phase-63 rule refresh
#
# Asserts that:
#   (a) rules/ctx-rules.md ctx_search row documents project: with three value forms
#       (omit, "global", <absolute-path>)
#   (b) rules/ctx-rules.md mentions sort: "timeline" and contentType
#   (c) rules/cmm-rules.md behavior-notes label contains v0.10.8 (not v0.8.1)
#   (d) rules/cmm-rules.md documents qualified_name (trace_path fallback)
#   (e) rules/cmm-rules.md mentions LSP (call graph accuracy)
#   (f) diff rules/ctx-rules.md .claude/rules/ctx-rules.md exits 0 (propagation check)
#   (g) diff rules/cmm-rules.md .claude/rules/cmm-rules.md exits 0 (propagation check)
#
# Usage: bash tests/test-phase-63-rule-refresh.sh
# Exit:  0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

PASS=0
FAIL=0
SKIP=0

_pass() {
  echo "  [PASS] $1"
  PASS=$((PASS + 1))
}

_fail() {
  echo "  [FAIL] $1"
  FAIL=$((FAIL + 1))
}

# A skipped check is NOT a passing check — it is counted and reported separately
# so an uninstalled repo can never read as verified.
_skip() {
  echo "  [SKIP] $1"
  SKIP=$((SKIP + 1))
}

_grep_assert() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -q "$pattern" "$file"; then
    _pass "$desc"
  else
    _fail "$desc"
  fi
}

_grep_absent() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -q "$pattern" "$file"; then
    _fail "$desc"
  else
    _pass "$desc"
  fi
}

_diff_assert() {
  local desc="$1"
  local file_a="$2"
  local file_b="$3"
  if diff -q "$file_a" "$file_b" >/dev/null 2>&1; then
    _pass "$desc"
  else
    _fail "$desc"
  fi
}

echo ""
echo "=== Phase 63: ctx-rules and cmm-rules refresh ==="
echo ""

echo "--- (a) ctx-rules: ctx_search row documents project: parameter ---"
_grep_assert "ctx-rules documents project: parameter" \
  'project:' "rules/ctx-rules.md"
_grep_assert "ctx-rules documents \"global\" value form" \
  '"global"' "rules/ctx-rules.md"
_grep_assert "ctx-rules documents <absolute-path> value form" \
  'absolute-path' "rules/ctx-rules.md"

echo ""
echo "--- (b) ctx-rules: sort: timeline and contentType documented ---"
_grep_assert "ctx-rules mentions sort: \"timeline\"" \
  'sort.*timeline\|timeline.*sort' "rules/ctx-rules.md"
_grep_assert "ctx-rules mentions contentType" \
  'contentType' "rules/ctx-rules.md"

echo ""
echo "--- (c) cmm-rules: behavior-notes label is v0.10.8, not v0.8.1 ---"
_grep_assert "cmm-rules label contains v0.10.8" \
  'v0\.10\.8' "rules/cmm-rules.md"
_grep_absent "cmm-rules label does not contain stale v0.8.1" \
  'v0\.8\.1' "rules/cmm-rules.md"

echo ""
echo "--- (d) cmm-rules: trace_path qualified_name fallback documented ---"
_grep_assert "cmm-rules documents qualified_name fallback" \
  'qualified_name' "rules/cmm-rules.md"

echo ""
echo "--- (e) cmm-rules: LSP call-graph accuracy note present + correct language set ---"
_grep_assert "cmm-rules mentions LSP" \
  'LSP' "rules/cmm-rules.md"
# Hybrid LSP set must match upstream v0.10.8 (README "Hybrid LSP ... and Perl";
# internal/cbm/lsp/perl_lsp.c). CUDA, Rust and Perl are all resolved languages.
_grep_assert "cmm-rules LSP set includes CUDA (resolved upstream)" \
  'C/C++/CUDA' "rules/cmm-rules.md"
_grep_assert "cmm-rules lists Rust among LSP-resolved languages" \
  'Kotlin, Rust' "rules/cmm-rules.md"
_grep_assert "cmm-rules lists Perl among LSP-resolved languages" \
  'Rust, and \*\*Perl\*\*' "rules/cmm-rules.md"
_grep_assert "cmm-rules treats Perl as a Hybrid LSP language, not a fallback" \
  'Perl is a Hybrid LSP language, not a fallback language' "rules/cmm-rules.md"
_grep_assert "cmm-rules forbids inferring non-support from an absent language" \
  'Never infer that a language is unsupported' "rules/cmm-rules.md"
_grep_assert "cmm-rules warns qn_pattern noise is not absence" \
  'name_pattern' "rules/cmm-rules.md"
# Pin the heuristics bullet by its OWN text. This assertion previously used the
# 'pessimistic assumption' phrase, which lives in the "never infer" bullet asserted
# two lines above — so it duplicated that coverage and left the heuristics bullet
# with none.
_grep_assert "cmm-rules notes unresolved languages fall back to heuristics" \
  'edges from heuristics' "rules/cmm-rules.md"
# The cross-file caveat is the correction QA round 6 required: Perl has per-file
# Hybrid LSP but is NOT in cbm_pxc_has_cross_lsp(). Overclaiming here is the same
# defect as the original omission, sign-flipped, so pin both halves.
_grep_assert "cmm-rules records that Perl lacks the cross-file LSP pass" \
  'does not run the dedicated cross-file LSP pass' "rules/cmm-rules.md"
_grep_assert "cmm-rules does not tell agents to trust Perl trace_path as on Go" \
  'confirm with .search_code.' "rules/cmm-rules.md"

# (f)/(g) verify that setup.sh PROPAGATED the source rules into the install target.
# `.claude/*` is gitignored, so on a fresh clone that directory does not exist until
# `bash setup.sh --project` has been run. Asserting there would report a defect in the
# rules where the only fact is "not installed yet" — so skip, visibly, naming the
# prerequisite. A skip is counted separately and never as a pass.
echo ""
if [ ! -d ".claude/rules" ]; then
  echo "--- (f)+(g) installed-rule propagation ---"
  _skip "propagation checks: .claude/rules/ absent — run 'bash setup.sh --project' first"
else
  echo "--- (f) installed .claude/rules/ctx-rules.md matches source ---"
  _diff_assert "diff rules/ctx-rules.md .claude/rules/ctx-rules.md exits 0" \
    "rules/ctx-rules.md" ".claude/rules/ctx-rules.md"

  echo ""
  echo "--- (g) installed .claude/rules/cmm-rules.md matches source ---"
  _diff_assert "diff rules/cmm-rules.md .claude/rules/cmm-rules.md exits 0" \
    "rules/cmm-rules.md" ".claude/rules/cmm-rules.md"
fi

# skills/cmm-rules/SKILL.md is a deliberately CONDENSED variant of rules/cmm-rules.md,
# so a diff guard would be the wrong instrument. But setup.sh installs it verbatim to
# both scopes, and nothing else pins its content — so a correction made in the rules
# could ship stale here forever. Pin the claims that matter, phrase-level.
echo ""
echo "--- cmm-rules SKILL.md carries the same Perl claims as the rules ---"
_grep_assert "SKILL.md lists Perl among LSP-resolved languages" \
  'Rust, and \*\*Perl\*\*' "skills/cmm-rules/SKILL.md"
_grep_assert "SKILL.md records the cross-file LSP caveat" \
  'does not run the dedicated cross-file LSP pass' "skills/cmm-rules/SKILL.md"
_grep_absent "SKILL.md does not claim Perl trace_path is as trustworthy as Go" \
  'exactly as on Go' "skills/cmm-rules/SKILL.md"
_grep_assert "SKILL.md forbids inferring non-support from an absent language" \
  'Never infer that a language is unsupported' "skills/cmm-rules/SKILL.md"
_grep_assert "SKILL.md states hooks DO fire inside subagents" \
  'do\*\* fire for tool calls made inside a subagent' "skills/cmm-rules/SKILL.md"
_grep_assert "SKILL.md scopes the bypass to the Agent spawn gate" \
  'agent-cmm-gate.sh' "skills/cmm-rules/SKILL.md"
_grep_absent "SKILL.md no longer cites the disproven #34692 claim" \
  '34692' "skills/cmm-rules/SKILL.md"

echo ""
echo "--- pre-existing notes still retained in cmm-rules ---"
_grep_assert "cmm-rules retains 200-row cap note" \
  '200' "rules/cmm-rules.md"
_grep_assert "cmm-rules retains search_code regex note" \
  'foo\.\*bar\|regex\|multi-word' "rules/cmm-rules.md"
_grep_assert "cmm-rules retains list_projects /tmp note" \
  '/tmp/' "rules/cmm-rules.md"

echo ""
echo "--- CHECKSUMS.sha256 verifies all entries ---"
if shasum -a 256 --check CHECKSUMS.sha256 >/dev/null 2>&1; then
  _pass "shasum -a 256 --check CHECKSUMS.sha256 exits 0"
else
  _fail "CHECKSUMS.sha256 verification failed"
fi

echo ""
if [ "$SKIP" -gt 0 ]; then
  echo "Results: $PASS passed, $FAIL failed, $SKIP skipped (skipped != verified)"
else
  echo "Results: $PASS passed, $FAIL failed"
fi
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
