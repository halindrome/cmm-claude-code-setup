#!/bin/bash
# test-phase-49-agent-sync.sh — Regression coverage for phase-49 agent sync to VBW v1.35.0
#
# Asserts that agents/vbw-*.md files carry both the VBW-v1.35.0 sync markers
# (write-verification.sh, plan_ref/plans_verified, Debug Session QA Mode,
# Pre-Existing Failure Handling, Tool blocks, ac_results, pre_existing_issues,
# skill_no_activation) AND preserve the CMM-only extensions (hooks: frontmatter,
# MAINTENANCE override comments, Context Mode Web Fetch block, CMM EXTENSION
# note for Task(vbw-debugger) self-spawn). Also verifies that the CMM-added
# tools: allowlist on vbw-qa was reverted and that CHECKSUMS.sha256 still
# verifies against the six agent files.
#
# Usage: bash tests/test-phase-49-agent-sync.sh
# Exit: 0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

PASS=0; FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

_assert_grep() {
    local label="$1" pattern="$2" file="$3"
    if grep -q -- "$pattern" "$file"; then
        _pass "$label"
    else
        _fail "$label (missing '$pattern' in $file)"
    fi
}

_assert_not_grep() {
    local label="$1" pattern="$2" file="$3"
    if grep -q -- "$pattern" "$file"; then
        _fail "$label (unexpected '$pattern' in $file)"
    else
        _pass "$label"
    fi
}

AGENTS=(vbw-dev vbw-scout vbw-lead vbw-qa vbw-debugger vbw-docs)

# 1. <skill_no_activation> across all 6 agents
for a in "${AGENTS[@]}"; do
    _assert_grep "skill_no_activation in $a.md" "skill_no_activation" "agents/${a}.md"
done

# 2. write-verification.sh in vbw-qa
_assert_grep "write-verification.sh in vbw-qa.md" "write-verification.sh" "agents/vbw-qa.md"

# 3. plan_ref + plans_verified in vbw-qa
_assert_grep "plan_ref in vbw-qa.md" "plan_ref" "agents/vbw-qa.md"
_assert_grep "plans_verified in vbw-qa.md" "plans_verified" "agents/vbw-qa.md"

# 4. Debug Session QA Mode section in vbw-qa
_assert_grep "Debug Session QA Mode in vbw-qa.md" "Debug Session QA Mode" "agents/vbw-qa.md"

# 5. Pre-Existing Failure Handling section in vbw-qa
_assert_grep "Pre-Existing Failure Handling in vbw-qa.md" "Pre-Existing Failure Handling" "agents/vbw-qa.md"

# 6. ## Tool blocks section in vbw-dev (CMM extension preserved)
_assert_grep "Tool blocks heading in vbw-dev.md" "^## Tool blocks" "agents/vbw-dev.md"

# 7. ac_results + pre_existing_issues in vbw-dev
_assert_grep "ac_results in vbw-dev.md" "ac_results" "agents/vbw-dev.md"
_assert_grep "pre_existing_issues in vbw-dev.md" "pre_existing_issues" "agents/vbw-dev.md"

# 8. Context Mode Web Fetch block preserved in vbw-dev (CMM extension)
_assert_grep "Context Mode Web Fetch in vbw-dev.md" "Context Mode Web Fetch" "agents/vbw-dev.md"

# 9. CMM EXTENSION note in vbw-debugger MAINTENANCE comment
_assert_grep "CMM EXTENSION in vbw-debugger.md" "CMM EXTENSION" "agents/vbw-debugger.md"

# 10. hooks: frontmatter block AND MAINTENANCE override comment in each of the 6 agents
for a in "${AGENTS[@]}"; do
    _assert_grep "hooks: frontmatter in $a.md" "^hooks:" "agents/${a}.md"
    _assert_grep "MAINTENANCE override comment in $a.md" "MAINTENANCE" "agents/${a}.md"
done

# 11. vbw-qa.md frontmatter has NO tools: line (allowlist reverted)
# Only check the frontmatter region (first 20 lines) since "tools:" may appear in body prose.
qa_frontmatter_tools=$(head -20 agents/vbw-qa.md | grep -c '^tools:' || true)
if [ "$qa_frontmatter_tools" = "0" ]; then
    _pass "vbw-qa.md frontmatter has no tools: allowlist"
else
    _fail "vbw-qa.md frontmatter unexpectedly has tools: line"
fi

# 12. CHECKSUMS.sha256 verifies (covers all 6 agent files)
if shasum -a 256 -c CHECKSUMS.sha256 >/dev/null 2>&1; then
    _pass "shasum -a 256 -c CHECKSUMS.sha256 exits 0"
else
    _fail "CHECKSUMS.sha256 verification failed"
fi

# Also confirm all phase-49-sync agents/vbw-*.md entries are present and OK.
# Use >= 6 (not equality) so additional tracked agents outside the phase 49
# VBW v1.35.0 sync scope (e.g. vbw-architect, added in phase 37) do not
# break this assertion once CHECKSUMS.sha256 rightly tracks them too.
agent_ok_count=$(shasum -a 256 -c CHECKSUMS.sha256 2>&1 | grep -cE 'agents/vbw-.*:.*OK')
if [ "$agent_ok_count" -ge 6 ]; then
    _pass "At least 6 agents/vbw-*.md entries verify OK in CHECKSUMS.sha256 (got $agent_ok_count)"
else
    _fail "Expected at least 6 agent entries OK, got $agent_ok_count"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
