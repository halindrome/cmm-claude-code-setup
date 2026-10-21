#!/bin/bash
# test-phase-66-delta-format.sh — Static assertions on agents/vbw-*.md delta format
#
# Asserts that all 7 agent source files conform to the delta-only architecture
# introduced in Phase 66: cmm-delta fences, SHA fields, no upstream VBW body
# text, and preserved phase-62 tool-grant surface.
# No mock fixtures needed — runs against actual agents/ source files.
#
# Usage: bash tests/test-phase-66-delta-format.sh
# Exit: 0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

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

AGENTS=(vbw-architect vbw-debugger vbw-dev vbw-docs vbw-lead vbw-qa vbw-scout)

echo ""
echo "=== Phase 66: delta-format static assertions on agents/vbw-*.md ==="
echo ""

# -----------------------------------------------------------------------
# 1. All 7 files have at least one cmm-delta:begin fence
# -----------------------------------------------------------------------
echo "--- 1: cmm-delta:begin fences present ---"
for a in "${AGENTS[@]}"; do
    _assert_grep "agents/${a}.md has cmm-delta:begin" "cmm-delta:begin" "agents/${a}.md"
done

# -----------------------------------------------------------------------
# 2. Fence balance: begin count == end count for each file
# -----------------------------------------------------------------------
echo "--- 2: fence balance (begin == end) ---"
for a in "${AGENTS[@]}"; do
    begins=$(grep -c 'cmm-delta:begin' "agents/${a}.md" 2>/dev/null || echo 0)
    ends=$(grep -c 'cmm-delta:end' "agents/${a}.md" 2>/dev/null || echo 0)
    if [ "$begins" -eq "$ends" ] && [ "$begins" -gt 0 ]; then
        _pass "agents/${a}.md: balanced fences (begin=$begins end=$ends)"
    else
        _fail "agents/${a}.md: balanced fences" "begin=$begins end=$ends"
    fi
done

# -----------------------------------------------------------------------
# 3. x-cmm-base-sha field exists in all 7 files
# -----------------------------------------------------------------------
echo "--- 3: x-cmm-base-sha field present ---"
for a in "${AGENTS[@]}"; do
    _assert_grep "agents/${a}.md has x-cmm-base-sha" "^x-cmm-base-sha:" "agents/${a}.md"
done

# -----------------------------------------------------------------------
# 4. x-cmm-delta-sha field exists in all 7 files
# -----------------------------------------------------------------------
echo "--- 4: x-cmm-delta-sha field present ---"
for a in "${AGENTS[@]}"; do
    _assert_grep "agents/${a}.md has x-cmm-delta-sha" "^x-cmm-delta-sha:" "agents/${a}.md"
done

# -----------------------------------------------------------------------
# 5. No upstream VBW body text in any of the 7 files
#    (these titles live in the VBW base; delta files must not copy them)
# -----------------------------------------------------------------------
echo "--- 5: no upstream VBW body text ---"
VBW_BODY_PATTERNS=(
    "## Planning Protocol"
    "## V2 Role Isolation"
    "^## Effort$"
    "## Goal-Backward Methodology"
)
for a in "${AGENTS[@]}"; do
    for pat in "${VBW_BODY_PATTERNS[@]}"; do
        _assert_not_grep "agents/${a}.md: absent '$pat'" "$pat" "agents/${a}.md"
    done
done

# -----------------------------------------------------------------------
# 6. hooks: frontmatter present in all 7 files
# -----------------------------------------------------------------------
echo "--- 6: hooks: frontmatter present ---"
for a in "${AGENTS[@]}"; do
    _assert_grep "agents/${a}.md has hooks: frontmatter" "^hooks:" "agents/${a}.md"
done

# -----------------------------------------------------------------------
# 7. skills: frontmatter present in all 7 files
# -----------------------------------------------------------------------
echo "--- 7: skills: frontmatter present ---"
for a in "${AGENTS[@]}"; do
    _assert_grep "agents/${a}.md has skills: frontmatter" "^skills:" "agents/${a}.md"
done

# -----------------------------------------------------------------------
# 8. Phase-62 tool-grant surface preserved
#    vbw-architect has disallowedTools: (not tools:) in frontmatter
#    vbw-debugger has tools: (not disallowedTools:) in frontmatter
# -----------------------------------------------------------------------
echo "--- 8: phase-62 tool-grant surface ---"

# vbw-architect: must have disallowedTools in frontmatter (first 40 lines)
arch_fm=$(head -40 agents/vbw-architect.md)
if echo "$arch_fm" | grep -q '^disallowedTools:'; then
    _pass "agents/vbw-architect.md: has disallowedTools: in frontmatter"
else
    _fail "agents/vbw-architect.md: has disallowedTools: in frontmatter" \
        "missing (or tools: used instead)"
fi
if echo "$arch_fm" | grep -q '^tools:'; then
    _fail "agents/vbw-architect.md: no tools: allowlist in frontmatter" \
        "unexpected tools: line found"
else
    _pass "agents/vbw-architect.md: no tools: allowlist in frontmatter"
fi

# vbw-debugger: must have tools: in frontmatter (first 40 lines) for CMM grants
dbg_fm=$(head -40 agents/vbw-debugger.md)
if echo "$dbg_fm" | grep -q '^tools:'; then
    _pass "agents/vbw-debugger.md: has tools: allowlist in frontmatter"
else
    _fail "agents/vbw-debugger.md: has tools: allowlist in frontmatter" \
        "missing (check phase-62 tool grants)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
