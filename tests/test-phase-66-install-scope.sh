#!/bin/bash
# test-phase-66-install-scope.sh — PROJECT-SCOPE-ONLY regression guard for
# agent-override-generate.sh in setup.sh.
#
# Asserts by scoping greps to install_project vs install_global function bodies:
#   1. install_project body DOES reference/register agent-override-generate.sh
#   2. install_global body does NOT reference agent-override-generate.sh
#   3. install_global body does NOT write .claude/agents/ (no mkdir/copy there)
#   4. The only agents/*.md copy/install loop is in install_project
#
# Rationale: deterministic guarantee that agent generation is project-mode-only.
# A project that never ran `setup.sh --project` gets no agent generation, and
# global install never touches VBW agents.
#
# Usage: bash tests/test-phase-66-install-scope.sh
# Exit: 0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

SETUP="$REPO_ROOT/setup.sh"
PASS=0; FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# -----------------------------------------------------------------------
# Extract line ranges for install_project and install_global function bodies.
# Strategy: find the line where each function is declared (^function_name()),
# then find the next top-level function or EOF as the end boundary.
# -----------------------------------------------------------------------
total_lines=$(wc -l <"$SETUP" | tr -d ' ')

# Find install_project start — strip any trailing whitespace/CR
ip_start=$(grep -n '^install_project()' "$SETUP" | head -1 | cut -d: -f1 | tr -d '[:space:]')
# Find install_global start
ig_start=$(grep -n '^install_global()' "$SETUP" | head -1 | cut -d: -f1 | tr -d '[:space:]')

if [ -z "${ip_start:-}" ] || [ -z "${ig_start:-}" ]; then
    echo "FAIL: Could not locate install_project() or install_global() in setup.sh"
    exit 1
fi

# install_project body: from its declaration to one line before install_global
# (whichever comes first). Handle either ordering.
if [ "$ip_start" -lt "$ig_start" ]; then
    ip_end=$((ig_start - 1))
    ig_end=$total_lines
else
    ig_end=$((ip_start - 1))
    ip_end=$total_lines
fi

# Extract bodies using awk
_body_of() {
    local start="$1" end="$2"
    awk "NR>=$start && NR<=$end" "$SETUP"
}

ip_body=$(_body_of "$ip_start" "$ip_end")
ig_body=$(_body_of "$ig_start" "$ig_end")

echo ""
echo "=== Phase 66: install-scope assertions (setup.sh) ==="
echo "install_project: lines $ip_start to $ip_end"
echo "install_global:  lines $ig_start to $ig_end"
echo ""

# -----------------------------------------------------------------------
# 1. install_project body DOES register agent-override-generate.sh
# -----------------------------------------------------------------------
echo "--- 1: install_project registers agent-override-generate.sh ---"
if echo "$ip_body" | grep -q 'agent-override-generate'; then
    _pass "install_project: references agent-override-generate.sh"
else
    _fail "install_project: references agent-override-generate.sh" \
        "not found in install_project body"
fi

# Also verify it's in the SessionStart context (hook registration)
if echo "$ip_body" | grep -qE 'agent-override-generate|SessionStart'; then
    _pass "install_project: SessionStart or agent-override-generate registration present"
else
    _fail "install_project: SessionStart or agent-override-generate registration present" \
        "neither SessionStart nor agent-override-generate found in install_project"
fi

# -----------------------------------------------------------------------
# 2. install_global body does NOT reference agent-override-generate.sh
# -----------------------------------------------------------------------
echo "--- 2: install_global does NOT reference agent-override-generate.sh ---"
if echo "$ig_body" | grep -q 'agent-override-generate'; then
    _fail "install_global: no agent-override-generate reference" \
        "unexpected agent-override-generate found in install_global"
else
    _pass "install_global: no agent-override-generate reference"
fi

# -----------------------------------------------------------------------
# 3. install_global body does NOT write to .claude/agents/
#    (no .claude/agents mkdir or copy in that function)
# -----------------------------------------------------------------------
echo "--- 3: install_global does NOT write .claude/agents/ ---"
if echo "$ig_body" | grep -qE '\.claude/agents'; then
    _fail "install_global: no .claude/agents write" \
        "unexpected .claude/agents reference found in install_global"
else
    _pass "install_global: no .claude/agents reference"
fi

if echo "$ig_body" | grep -qE 'agents/\*\.md|agents/vbw'; then
    _fail "install_global: no agents/*.md copy loop" \
        "unexpected agents/*.md or agents/vbw reference in install_global"
else
    _pass "install_global: no agents/*.md copy loop"
fi

# -----------------------------------------------------------------------
# 4. The only agents/*.md install/copy loop lives in install_project
# -----------------------------------------------------------------------
echo "--- 4: agents/ copy/install loop only in install_project ---"

# Check install_project has the agent install section
if echo "$ip_body" | grep -qE '\.claude/agents|agent-override-generate|agents/.*\.md'; then
    _pass "install_project: has agent install section"
else
    _fail "install_project: has agent install section" \
        "no .claude/agents or agent-override-generate in install_project body"
fi

# Confirm global scope has zero agent copy operations
if echo "$ig_body" | grep -qE '\.claude/agents|agents/\*\.md'; then
    _fail "install_global: zero .claude/agents or agents/*.md operations" \
        "unexpected match found in install_global body"
else
    _pass "install_global: zero .claude/agents or agents/*.md operations"
fi

# -----------------------------------------------------------------------
# 5. Whole-file sanity: agent-override-generate.sh referenced in setup.sh at all
# -----------------------------------------------------------------------
echo "--- 5: sanity — agent-override-generate.sh appears in setup.sh ---"
total_refs=$(grep -c 'agent-override-generate' "$SETUP" 2>/dev/null || echo 0)
if [ "$total_refs" -ge 1 ]; then
    _pass "setup.sh: agent-override-generate.sh referenced at least once (count=$total_refs)"
else
    _fail "setup.sh: agent-override-generate.sh referenced at least once" \
        "zero references — hook may not be registered"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
