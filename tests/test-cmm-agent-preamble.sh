#!/bin/bash
# test-cmm-agent-preamble.sh — Tests for the reusable CMM/ctx subagent preamble asset,
# the agent-cmm-gate DRY emission + inline fallback, the strengthened SubagentStart
# injection, and the docs that explain why the preamble is needed despite hooks
# reaching subagents (reach is solved; adoption is not — measured 2026-09-03).
# Usage: bash tests/test-cmm-agent-preamble.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ASSET="$ROOT/rules/cmm-agent-preamble.md"
GATE="$ROOT/hooks/project/agent-cmm-gate.sh"
STARTUP="$ROOT/hooks/project/subagent-cmm-startup.sh"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
_has() { # _has <label> <file> <substring>
  if grep -qF -- "$3" "$2"; then pass "$1"; else fail "$1 (missing: $3)"; fi
}
_lacks() { # _lacks <label> <file> <substring>
  if grep -qF -- "$3" "$2"; then fail "$1 (still present: $3)"; else pass "$1"; fi
}

echo "--- Asset exists and is well-formed ---"
if [ -f "$ASSET" ]; then pass "asset present: rules/cmm-agent-preamble.md"; else fail "asset missing"; fi
_has "asset has 'copy from here' marker"  "$ASSET" "--- copy from here ---"
_has "asset has 'copy to here' marker"    "$ASSET" "--- copy to here ---"

echo "--- Asset copy-region carries the required tool vocabulary ---"
# Extract only the pasteable region and assert the key tool names are inside it.
REGION="$(awk '/^--- copy from here ---$/{f=1;next} /^--- copy to here ---$/{f=0} f' "$ASSET")"
for tok in search_graph get_code_snippet trace_path get_architecture query_graph search_code \
           ctx_execute ctx_batch_execute ctx_search; do
  if printf '%s' "$REGION" | grep -qF "$tok"; then
    pass "copy-region contains $tok"
  else
    fail "copy-region missing $tok"
  fi
done

echo "--- Gate emits the asset copy-region (installed layout) and blocks (exit 2) ---"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/hooks" "$TMP/rules"
cp "$GATE" "$TMP/hooks/agent-cmm-gate.sh"
cp "$ASSET" "$TMP/rules/cmm-agent-preamble.md"
NOKW='{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"refactor the function in this file and the class method to fix a debug issue in the module"}}'
rc=0
OUT="$(echo "$NOKW" | bash "$TMP/hooks/agent-cmm-gate.sh" 2>&1)" || rc=$?
if [ "$rc" -eq 2 ]; then pass "gate blocks missing-keyword prompt (exit 2)"; else fail "gate exit expected 2, got $rc"; fi
if printf '%s' "$OUT" | grep -qF "search_graph" && printf '%s' "$OUT" | grep -qF "ctx_execute"; then
  pass "gate emitted preamble tool vocabulary from asset"
else
  fail "gate did not emit preamble tool vocabulary"
fi
if printf '%s' "$OUT" | grep -qiF "bypass this gate" || printf '%s' "$OUT" | grep -qiF "bypass"; then
  pass "gate warns Workflow agent() prompts bypass it"
else
  fail "gate missing Workflow-bypass warning"
fi

echo "--- Gate inline fallback fires when the asset is absent ---"
mkdir -p "$TMP/hooks-nofallback"
cp "$GATE" "$TMP/hooks-nofallback/agent-cmm-gate.sh"   # no sibling ../rules asset
rc=0
OUT2="$(echo "$NOKW" | bash "$TMP/hooks-nofallback/agent-cmm-gate.sh" 2>&1)" || rc=$?
if [ "$rc" -eq 2 ]; then pass "fallback blocks (exit 2)"; else fail "fallback exit expected 2, got $rc"; fi
if printf '%s' "$OUT2" | grep -qF "Copy-paste" && printf '%s' "$OUT2" | grep -qF "search_graph"; then
  pass "fallback emits inline copy-paste block"
else
  fail "fallback missing inline block"
fi

echo "--- Gate still ALLOWS a prompt that already references CMM tools (exit 0) ---"
rc=0
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Use search_graph to find the Handler class"}}' \
  | bash "$TMP/hooks/agent-cmm-gate.sh" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then pass "CMM-referencing prompt allowed (exit 0)"; else fail "expected exit 0, got $rc"; fi

echo "--- SubagentStart injection strengthened but preserves Skill activations ---"
_has "startup: adds concrete CMM tool mandate"   "$STARTUP" "Prefer CMM graph tools"
_has "startup: adds ctx routing mandate"         "$STARTUP" "ctx_batch_execute"
_has "startup: preserves cmm-rules Skill call"   "$STARTUP" "Invoke Skill('cmm-rules')"
_has "startup: preserves ctx-rules Skill call"   "$STARTUP" "Invoke Skill('ctx-rules')"

echo "--- Docs explain the real limitation and point at the asset ---"
# Measured 2026-09-03: PreToolUse hooks DO fire inside subagents on every CC version
# 2.1.175-2.1.260. The old assertions pinned the disproven #34692 claim; these pin the
# corrected wording so the rewrite cannot silently regress.
_has "cmm-rules: states hooks do fire in subagents" "$ROOT/rules/cmm-rules.md" "**do** fire inside subagents"
_has "cmm-rules: scopes bypass to the spawn gate"   "$ROOT/rules/cmm-rules.md" "agent-cmm-gate.sh"
_has "cmm-rules: justifies preamble on adoption"    "$ROOT/rules/cmm-rules.md" "**zero** CMM calls"
_has "cmm-rules: points at preamble asset"       "$ROOT/rules/cmm-rules.md" "cmm-agent-preamble.md"
_has "ctx-rules: states hooks do fire in subagents" "$ROOT/rules/ctx-rules.md" "**do** fire for tool calls"
_has "ctx-rules: points at preamble asset"       "$ROOT/rules/ctx-rules.md" "cmm-agent-preamble.md"
_has "preamble: states hooks do reach the agent"    "$ROOT/rules/cmm-agent-preamble.md" "Hooks **do** reach inside a running subagent"
_lacks "cmm-rules: stale #34692 claim removed"   "$ROOT/rules/cmm-rules.md" "34692"
_lacks "ctx-rules: stale #34692 claim removed"   "$ROOT/rules/ctx-rules.md" "34692"
_lacks "preamble: stale #34692 claim removed"    "$ROOT/rules/cmm-agent-preamble.md" "34692"
_has "README: references preamble asset"         "$ROOT/README.md" "cmm-agent-preamble.md"
_has "README: notes Workflow bypass"             "$ROOT/README.md" "bypass"
# CONTRIBUTING carried the same stale claim ("SubagentStart hooks cannot
# intercept tool calls inside the subagent") and was corrected by WS3, but
# nothing pinned it — absence of a pin is how a correction silently regresses.
# NB: skills/ctx-rules/SKILL.md has no subagent section at all, so it never
# carried the claim and there is nothing to assert there.
#
# Pin the POSITIVE claim, not the absence of a phrase. "cannot intercept tool
# calls" still appears there and is correct in its own sentence — SubagentStart
# is a startup hook and genuinely cannot; what was wrong was concluding that
# PreToolUse therefore does not reach the subagent either. Banning the phrase
# would forbid a true statement.
_lacks "CONTRIBUTING: stale #34692 claim removed" "$ROOT/CONTRIBUTING.md" "34692"
_has "CONTRIBUTING: states PreToolUse does fire in subagents" \
  "$ROOT/CONTRIBUTING.md" "**do** fire on tool calls made inside a subagent"
_has "CONTRIBUTING: scopes the bypass to the spawn gate" \
  "$ROOT/CONTRIBUTING.md" "agent-cmm-gate.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
