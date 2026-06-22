#!/bin/bash
# test-phase-49-agent-sync.sh — Regression coverage for phase-49 agent sync to VBW v1.35.0
#
# Phase 66 architectural update: agents/vbw-*.md are now DELTA-ONLY source files
# (frontmatter patch + cmm-delta fenced sections). VBW body content (skill_no_activation,
# plan_ref, plans_verified, Debug Session QA Mode, Pre-Existing Failure Handling,
# ac_results, pre_existing_issues) now lives in the upstream VBW base and is NOT
# present in these source files. Assertions updated accordingly:
#   - VBW body content: asserted ABSENT from delta sources (correct by design)
#   - CMM extensions (hooks:, MAINTENANCE, Tool blocks, Context Mode Web Fetch,
#     CMM EXTENSION): still asserted PRESENT (these are in our cmm-delta sections)
#   - CHECKSUMS.sha256: covers all 7 delta source files
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
# Phase 66 added vbw-architect; include in SHA coverage check
ALL_AGENTS=(vbw-architect vbw-dev vbw-scout vbw-lead vbw-qa vbw-debugger vbw-docs)

# --------------------------------------------------------------------------
# 1. VBW body content is ABSENT from delta source files (Phase 66 arch)
# These items were phase-49 additions to the VBW base body. Under delta-only
# architecture the source agents/vbw-*.md files contain ONLY frontmatter +
# cmm-delta fenced sections — no verbatim VBW body text.
# --------------------------------------------------------------------------
for a in "${AGENTS[@]}"; do
    _assert_not_grep "skill_no_activation absent from delta source $a.md (now in VBW base)" \
        "skill_no_activation" "agents/${a}.md"
done

# VBW-body keywords absent from delta sources (lives in VBW base, not our delta)
_assert_not_grep "plan_ref absent from vbw-qa.md delta source (VBW base)" \
    "plan_ref" "agents/vbw-qa.md"
_assert_not_grep "plans_verified absent from vbw-qa.md delta source (VBW base)" \
    "plans_verified" "agents/vbw-qa.md"
_assert_not_grep "Debug Session QA Mode absent from vbw-qa.md delta source (VBW base)" \
    "Debug Session QA Mode" "agents/vbw-qa.md"
_assert_not_grep "Pre-Existing Failure Handling absent from vbw-qa.md delta source (VBW base)" \
    "Pre-Existing Failure Handling" "agents/vbw-qa.md"
_assert_not_grep "ac_results absent from vbw-dev.md delta source (VBW base)" \
    "ac_results" "agents/vbw-dev.md"
_assert_not_grep "pre_existing_issues absent from vbw-dev.md delta source (VBW base)" \
    "pre_existing_issues" "agents/vbw-dev.md"

# write-verification.sh: appears in vbw-qa description frontmatter field (not body)
# This is a frontmatter field that IS part of our delta — assert it's still there
_assert_grep "write-verification.sh in vbw-qa.md description field" \
    "write-verification.sh" "agents/vbw-qa.md"

# --------------------------------------------------------------------------
# 2-3. CMM-extension delta content PRESENT in source files
# These live in our cmm-delta fenced sections and must survive all syncs.
# --------------------------------------------------------------------------

# Tool blocks section in vbw-dev (CMM delta section)
_assert_grep "Tool blocks heading in vbw-dev.md" "^## Tool blocks" "agents/vbw-dev.md"

# Context Mode Web Fetch block in vbw-dev (CMM delta section)
_assert_grep "Context Mode Web Fetch in vbw-dev.md" "Context Mode Web Fetch" "agents/vbw-dev.md"

# CMM EXTENSION note in vbw-debugger MAINTENANCE comment (CMM delta section)
_assert_grep "CMM EXTENSION in vbw-debugger.md" "CMM EXTENSION" "agents/vbw-debugger.md"

# hooks: frontmatter AND MAINTENANCE override comment in each of the 6 agents
for a in "${AGENTS[@]}"; do
    _assert_grep "hooks: frontmatter in $a.md" "^hooks:" "agents/${a}.md"
    _assert_grep "MAINTENANCE override comment in $a.md" "MAINTENANCE" "agents/${a}.md"
done

# --------------------------------------------------------------------------
# 4. vbw-qa.md frontmatter has NO tools: allowlist (disallowedTools used instead)
# Only check the frontmatter region (first 20 lines).
# --------------------------------------------------------------------------
qa_frontmatter_tools=$(head -20 agents/vbw-qa.md | grep -c '^tools:' || true)
if [ "$qa_frontmatter_tools" = "0" ]; then
    _pass "vbw-qa.md frontmatter has no tools: allowlist"
else
    _fail "vbw-qa.md frontmatter unexpectedly has tools: line"
fi

# --------------------------------------------------------------------------
# 5. CHECKSUMS.sha256 verifies all 7 agent delta source files
# (Phase 66 added vbw-architect; threshold updated to >= 7)
# --------------------------------------------------------------------------
if shasum -a 256 -c CHECKSUMS.sha256 >/dev/null 2>&1; then
    _pass "shasum -a 256 -c CHECKSUMS.sha256 exits 0"
else
    _fail "CHECKSUMS.sha256 verification failed"
fi

agent_ok_count=$(shasum -a 256 -c CHECKSUMS.sha256 2>&1 | grep -cE 'agents/vbw-.*:.*OK')
if [ "$agent_ok_count" -ge 7 ]; then
    _pass "At least 7 agents/vbw-*.md entries verify OK in CHECKSUMS.sha256 (got $agent_ok_count)"
else
    _fail "Expected at least 7 agent entries OK, got $agent_ok_count"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
