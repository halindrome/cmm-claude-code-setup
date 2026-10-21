#!/bin/bash
# test-cmm-agent-passthrough.sh — Tests for the per-project CMM spawn-gate
# pass-through allow-list (.claude/cmm-agent-passthrough.txt) in agent-cmm-gate.sh,
# and confirmation that vbw:* is no longer a built-in exemption.
# Usage: bash tests/test-cmm-agent-passthrough.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$SCRIPT_DIR/../hooks/project/agent-cmm-gate.sh"

PASS=0; FAIL=0
# Run the gate from an installed-style layout ($TMP/hooks/agent-cmm-gate.sh) so its
# sibling lookup ($_GATE_DIR/../cmm-agent-passthrough.txt) resolves to $TMP/cmm-...
_run_gate() { # _run_gate <tmpdir> <json>  -> echoes exit code
  local tmp="$1" json="$2" rc=0
  echo "$json" | bash "$tmp/hooks/agent-cmm-gate.sh" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
_assert() { # _assert <label> <expected-exit> <tmpdir> <json>
  local label="$1" expected="$2" tmp="$3" json="$4"
  local actual; actual="$(_run_gate "$tmp" "$json")"
  if [ "$actual" -eq "$expected" ]; then echo "PASS: $label"; PASS=$((PASS+1))
  else echo "FAIL: $label (expected exit $expected, got $actual)"; FAIL=$((FAIL+1)); fi
}

# A code-signal prompt with NO CMM keywords — gated unless the type is exempt.
CODE_PROMPT="Look at the function in this file and refactor the class method in the module"
mk_json() { printf '{"tool_name":"Agent","tool_input":{"subagent_type":"%s","prompt":"%s"}}' "$1" "$CODE_PROMPT"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/hooks"
cp "$GATE" "$TMP/hooks/agent-cmm-gate.sh"

echo "--- No config present: normal gating (blocked) ---"
_assert "no config: mr-qa-reviewer blocked" 2 "$TMP" "$(mk_json mr-qa-reviewer)"
_assert "no config: vbw:vbw-dev blocked (vbw:* no longer built-in exempt)" 2 "$TMP" "$(mk_json 'vbw:vbw-dev')"

echo "--- Config with literal + glob + comments ---"
cat > "$TMP/cmm-agent-passthrough.txt" <<'CFG'
# project pass-through list
mr-qa-reviewer

  mr-qa-manager   # indented + trailing comment
my-review-*
vbw:*
CFG

_assert "literal match: mr-qa-reviewer exempt (exit 0)"        0 "$TMP" "$(mk_json mr-qa-reviewer)"
_assert "literal match (indented+comment): mr-qa-manager exempt" 0 "$TMP" "$(mk_json mr-qa-manager)"
_assert "glob match: my-review-lens exempt via my-review-*"    0 "$TMP" "$(mk_json my-review-lens)"
_assert "glob match: vbw:vbw-dev exempt via vbw:*"             0 "$TMP" "$(mk_json 'vbw:vbw-dev')"
_assert "not listed: dev still blocked"                        2 "$TMP" "$(mk_json dev)"
_assert "not listed: mr-qa-reviewerX (no glob) blocked"        2 "$TMP" "$(mk_json mr-qa-reviewerX)"

echo "--- Exempted type still allowed even though prompt has no CMM keywords, but keyword prompt is allowed too ---"
_assert "listed type + CMM keyword prompt still exit 0" 0 "$TMP" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"mr-qa-reviewer","prompt":"Use search_graph to inspect the module"}}'

echo "--- Comment-only / blank config never exempts ---"
printf '# only comments\n\n   \n' > "$TMP/cmm-agent-passthrough.txt"
_assert "comment-only config: mr-qa-reviewer blocked" 2 "$TMP" "$(mk_json mr-qa-reviewer)"

echo "--- Built-in exemptions still work (claude-code-guide) regardless of config ---"
rm -f "$TMP/cmm-agent-passthrough.txt"
_assert "built-in claude-code-guide exempt" 0 "$TMP" "$(mk_json claude-code-guide)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
