#!/bin/bash
# test-phase-66-generate.sh — Tests for hooks/project/agent-override-generate.sh
#
# Covers: SHA-stamp compare (no regen), SHA mismatch triggers regen, missing
# installed file triggers regen, merge correctness, fail-open on absent VBW,
# manual-edit detection warns and skips.
# Uses a temp fixture dir with a mock VBW agents/ tree.
#
# Usage: bash tests/test-phase-66-generate.sh
# Exit: 0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
HOOK="$REPO_ROOT/hooks/project/agent-override-generate.sh"
LIB="$REPO_ROOT/hooks/lib/vbw-source.sh"

PASS=0; FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

_assert_grep() {
    local label="$1" pattern="$2" file="$3"
    if grep -q -- "$pattern" "$file" 2>/dev/null; then
        _pass "$label"
    else
        _fail "$label" "missing '$pattern' in $file"
    fi
}

_assert_not_grep() {
    local label="$1" pattern="$2" file="$3"
    if grep -q -- "$pattern" "$file" 2>/dev/null; then
        _fail "$label" "unexpected '$pattern' in $file"
    else
        _pass "$label"
    fi
}

# -----------------------------------------------------------------------
# Fixture: scratch project + mock VBW agents tree
# -----------------------------------------------------------------------
TMPROOT=$(mktemp -d -t vbw-generate-test-XXXXXX)
trap 'rm -rf "$TMPROOT"' EXIT

SCRATCH="$TMPROOT/project"
FAKE_CONFIG="$TMPROOT/claude-config"
MKT="vbw-marketplace"
VBW_VERSION="1.99.0"
FAKE_VBW="$FAKE_CONFIG/plugins/cache/$MKT/vbw/$VBW_VERSION"
FAKE_VBW_AGENTS="$FAKE_VBW/agents"

mkdir -p "$SCRATCH/.claude/agents"
mkdir -p "$SCRATCH/.claude/hooks"
mkdir -p "$SCRATCH/.claude/rules"
mkdir -p "$FAKE_VBW_AGENTS"

# Minimal git repo so the hook can resolve project root
(cd "$SCRATCH" && git init -q && git commit --allow-empty -q -m "init")

# Install the hooks/lib into .claude/hooks/lib/ so project-root detection works
mkdir -p "$SCRATCH/.claude/hooks/lib"
cp "$REPO_ROOT/hooks/lib/project-root.sh" "$SCRATCH/.claude/hooks/lib/"
cp "$REPO_ROOT/hooks/lib/vbw-source.sh" "$SCRATCH/.claude/hooks/lib/"

# Install the generate hook into .claude/hooks/
cp "$HOOK" "$SCRATCH/.claude/hooks/agent-override-generate.sh"
chmod +x "$SCRATCH/.claude/hooks/agent-override-generate.sh"

# Install delta files into .claude/agents-delta/ (the primary installed-path resolution).
# This mirrors what setup.sh --project does in production and confirms the hook
# reads from the installed location independent of any repo checkout.
mkdir -p "$SCRATCH/.claude/agents-delta"
for _ag in architect debugger dev docs lead qa scout; do
  cp "$REPO_ROOT/agents/vbw-${_ag}.md" "$SCRATCH/.claude/agents-delta/"
done

# Create mock installed_plugins.json pointing to our fake VBW tree
mkdir -p "$FAKE_CONFIG/plugins"
cat >"$FAKE_CONFIG/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "vbw@vbw-marketplace": [
      {
        "installPath": "$FAKE_VBW",
        "version": "$VBW_VERSION",
        "scope": "user"
      }
    ]
  },
  "enabledPlugins": {
    "vbw@vbw-marketplace": true
  }
}
JSON

# Create minimal VBW base agent files for all 7 agents in the mock agents dir
for _agent in architect debugger dev docs lead qa scout; do
  cat >"$FAKE_VBW_AGENTS/vbw-${_agent}.md" <<VBWBASE
---
name: vbw-${_agent}
description: VBW ${_agent} agent (upstream base)
model: inherit
memory: project
permissionMode: default
---

# Execution agent (${_agent})

You are the VBW ${_agent^} agent.

## Planning Protocol

Plans before building.

## V2 Role Isolation

MUST NOT touch .vbw-planning/.contracts/.
VBWBASE
done

# Run helper: execute the generate hook inside the scratch project
_run_hook() {
    # Run the hook that was copied into .claude/hooks/ (not the repo source)
    (cd "$SCRATCH" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash ".claude/hooks/agent-override-generate.sh" 2>&1)
}

echo ""
echo "=== Phase 66: agent-override-generate.sh hook tests ==="
echo ""

# -----------------------------------------------------------------------
# T1 — Missing installed file triggers regen
# -----------------------------------------------------------------------
echo "--- T1: Missing installed file triggers regen ---"
rm -f "$SCRATCH/.claude/agents/vbw-dev.md"

_run_hook >/dev/null 2>&1 || true

if [ -f "$SCRATCH/.claude/agents/vbw-dev.md" ]; then
    _pass "T1: vbw-dev.md generated when missing"
else
    _fail "T1: vbw-dev.md generated when missing" "file still absent after hook run"
fi

# -----------------------------------------------------------------------
# T2 — Merge correctness: generated file has expected structure
# -----------------------------------------------------------------------
echo "--- T2: Merge correctness ---"
GEN="$SCRATCH/.claude/agents/vbw-dev.md"

# Must have "do not edit manually" header comment
_assert_grep "T2: generated file has 'do not edit manually' header" \
    "do not edit manually" "$GEN"

# Must contain at least one cmm-delta fence from the source delta file
# (the delta file agents/vbw-dev.md lives in the repo root)
if grep -q 'cmm-delta:begin' "$REPO_ROOT/agents/vbw-dev.md" 2>/dev/null; then
    _assert_grep "T2: generated file contains cmm-delta fence" \
        "cmm-delta:begin" "$GEN"
else
    _pass "T2: generated file contains cmm-delta fence (no delta in source — skipped)"
fi

# Must contain hooks: frontmatter from our delta
_assert_grep "T2: generated file contains hooks: frontmatter" "^hooks:" "$GEN"

# Must contain skills: frontmatter from our delta
_assert_grep "T2: generated file contains skills: frontmatter" "^skills:" "$GEN"

# Must contain x-cmm-base-sha stamp (non-empty value)
if grep -qE '^x-cmm-base-sha: ".+"' "$GEN" 2>/dev/null; then
    _pass "T2: x-cmm-base-sha stamped with non-empty value"
else
    _fail "T2: x-cmm-base-sha stamped with non-empty value" \
        "$(grep 'x-cmm-base-sha' "$GEN" 2>/dev/null || echo 'field missing')"
fi

# Must contain x-cmm-delta-sha stamp (non-empty value)
if grep -qE '^x-cmm-delta-sha: ".+"' "$GEN" 2>/dev/null; then
    _pass "T2: x-cmm-delta-sha stamped with non-empty value"
else
    _fail "T2: x-cmm-delta-sha stamped with non-empty value" \
        "$(grep 'x-cmm-delta-sha' "$GEN" 2>/dev/null || echo 'field missing')"
fi

# Must contain VBW base body text (from mock agent)
_assert_grep "T2: generated file contains VBW base body text" \
    "Execution agent" "$GEN"

# -----------------------------------------------------------------------
# T3 — SHA match → no regen (file mtime unchanged)
# -----------------------------------------------------------------------
echo "--- T3: SHA match suppresses regen (idempotent) ---"
# Record mtime before second run
mtime_before=$(stat -f '%m' "$GEN" 2>/dev/null || stat -c '%Y' "$GEN" 2>/dev/null)
sleep 1
_run_hook >/dev/null 2>&1 || true
mtime_after=$(stat -f '%m' "$GEN" 2>/dev/null || stat -c '%Y' "$GEN" 2>/dev/null)

if [ "$mtime_before" = "$mtime_after" ]; then
    _pass "T3: No regen when SHAs match (mtime unchanged)"
else
    _fail "T3: No regen when SHAs match (mtime unchanged)" \
        "mtime changed from $mtime_before to $mtime_after"
fi

# -----------------------------------------------------------------------
# T4 — Upstream (base) source change triggers regen of an UNEDITED override
#   A legitimate version update changes the SOURCE, not the installed file.
#   The content-sha guard must NOT mistake this for a manual edit.
# -----------------------------------------------------------------------
echo "--- T4: Source change triggers regen ---"
# Clean baseline, then bump the upstream base source so compute_base_sha differs.
rm -f "$GEN"
_run_hook >/dev/null 2>&1 || true
printf '\n## New Upstream Section\n\nAdded by upstream.\n' >> "$FAKE_VBW_AGENTS/vbw-dev.md"

hook_output=$(_run_hook 2>&1 || true)

# The unedited override should be regenerated with the new upstream content.
if grep -q "New Upstream Section" "$GEN" 2>/dev/null; then
    _pass "T4: unedited override regenerated after upstream source change"
else
    _fail "T4: unedited override regenerated after upstream source change" \
        "new upstream content not present in regenerated file"
fi

# Advisory or regeneration message should appear in hook output
if echo "$hook_output" | grep -qiE 'regenerat|restart|refresh|generat'; then
    _pass "T4: Hook output mentions regeneration"
else
    _fail "T4: Hook output mentions regeneration" \
        "hook_output: $(echo "$hook_output" | head -5)"
fi

# -----------------------------------------------------------------------
# T5 — Fail-open on VBW absent
# -----------------------------------------------------------------------
echo "--- T5: Fail-open when VBW absent ---"
ABSENT_CONFIG="$TMPROOT/absent-config"
mkdir -p "$ABSENT_CONFIG"

hook_rc=0
(cd "$SCRATCH" && CLAUDE_CONFIG_DIR="$ABSENT_CONFIG" bash ".claude/hooks/agent-override-generate.sh" 2>/dev/null) || hook_rc=$?

if [ "$hook_rc" -eq 0 ]; then
    _pass "T5: Hook exits 0 (fail-open) when VBW absent"
else
    _fail "T5: Hook exits 0 (fail-open) when VBW absent" "got exit $hook_rc"
fi

# -----------------------------------------------------------------------
# T6 — Manual-edit guard: warns AND preserves edits (discriminating, both paths)
#   Scenario A: hand edit, source unchanged → guard must warn + preserve.
#   Scenario B: hand edit + upstream source change (a regen is due) → guard must
#               warn + preserve and NOT clobber. This is the F-01 regression test:
#               it FAILS if a base/delta bump silently overwrites a hand edit.
# -----------------------------------------------------------------------
echo "--- T6a: Manual edit, source unchanged → warn + preserve ---"
rm -f "$GEN"
_run_hook >/dev/null 2>&1 || true
echo "# MANUAL EDIT A" >> "$GEN"
outA=$(_run_hook 2>&1 || true)

if grep -q "MANUAL EDIT A" "$GEN" 2>/dev/null; then
    _pass "T6a: hand edit preserved (not clobbered)"
else
    _fail "T6a: hand edit preserved (not clobbered)" "injected line was removed"
fi
if echo "$outA" | grep -qiE 'manual|edited'; then
    _pass "T6a: manual-edit warning emitted"
else
    _fail "T6a: manual-edit warning emitted" "no manual-edit warning in hook output"
fi

echo "--- T6b: Manual edit + upstream source change → warn + preserve, no clobber [F-01] ---"
rm -f "$GEN"
_run_hook >/dev/null 2>&1 || true
echo "# MANUAL EDIT B" >> "$GEN"
# Bump the upstream base so a regen would normally fire for this agent.
printf '\n## Another Upstream Section\n\nForces a regen.\n' >> "$FAKE_VBW_AGENTS/vbw-dev.md"
outB=$(_run_hook 2>&1 || true)

# CRITICAL: the guard must run BEFORE regen and preserve the edit.
if grep -q "MANUAL EDIT B" "$GEN" 2>/dev/null; then
    _pass "T6b: hand edit preserved despite pending regen (no silent clobber)"
else
    _fail "T6b: hand edit preserved despite pending regen (no silent clobber)" \
        "edit was clobbered by regen — F-01 regression"
fi
# Regen must have been skipped, so the new upstream content must NOT appear.
if grep -q "Another Upstream Section" "$GEN" 2>/dev/null; then
    _fail "T6b: regen skipped while edit present" \
        "regen ran and overwrote the edited file"
else
    _pass "T6b: regen skipped while edit present"
fi
if echo "$outB" | grep -qiE 'manual|edited'; then
    _pass "T6b: manual-edit warning emitted"
else
    _fail "T6b: manual-edit warning emitted" "no manual-edit warning in hook output"
fi

# -----------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
