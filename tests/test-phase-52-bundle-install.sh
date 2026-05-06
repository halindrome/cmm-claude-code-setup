#!/bin/bash
# test-phase-52-bundle-install.sh — Integration smoke test for Phase 52 agent bundle install
# Verifies that setup.sh --project installs the six Phase 52-modified agent override
# files (vbw-{dev,scout,lead,qa,debugger,docs}.md) into .claude/agents/, that each
# carries the body content asserted by Plan 52-01 (write-verification.sh, pre_existing_issues,
# <skill_no_activation>, CMM rationale comments), and that re-running setup is idempotent
# (no duplicate files, byte-stable settings.json hash, content hashes unchanged).
# Models its structure on tests/test-phase-47-bundle-install.sh.
# Usage: bash tests/test-phase-52-bundle-install.sh
# Exit: 0 = all pass, 1 = any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PASS=0; FAIL=0

_assert() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label"
        FAIL=$((FAIL+1))
    fi
}

# Create scratch project dir (temp dir cleaned on exit).
SCRATCH=$(mktemp -d -t cmm-phase52-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

cd "$SCRATCH"

# Minimal git repo so setup.sh --project has a project root to anchor to.
git init -q
git commit --allow-empty -q -m "init"

# Run install (non-interactive, skip MCP availability check).
echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project first run exited non-zero"
    exit 1
}

# --- All six Phase 52 agent override files are installed ---
for agent in vbw-dev vbw-scout vbw-lead vbw-qa vbw-debugger vbw-docs; do
    _assert ".claude/agents/${agent}.md installed" \
        test -f ".claude/agents/${agent}.md"
done

# --- Body-content assertions: one keyword per agent confirming Plan 52-01 content landed ---

# vbw-qa.md must reference write-verification.sh (Plan 52-01 T02)
_assert "vbw-qa.md contains 'write-verification.sh' keyword" \
    grep -q 'write-verification.sh' ".claude/agents/vbw-qa.md"

# vbw-dev.md must contain pre_existing_issues (Plan 52-01 T03; expect >= 2 occurrences in source)
_assert "vbw-dev.md contains 'pre_existing_issues' keyword (>=2)" \
    bash -c "[ \"\$(grep -c 'pre_existing_issues' .claude/agents/vbw-dev.md)\" -ge 2 ]"

# vbw-scout.md must contain <skill_no_activation> (Plan 52-01 T04)
_assert "vbw-scout.md contains '<skill_no_activation>' keyword" \
    grep -q '<skill_no_activation>' ".claude/agents/vbw-scout.md"

# vbw-lead.md must contain <skill_no_activation> (Plan 52-01 T04)
_assert "vbw-lead.md contains '<skill_no_activation>' keyword" \
    grep -q '<skill_no_activation>' ".claude/agents/vbw-lead.md"

# vbw-docs.md must contain <skill_no_activation> (Plan 52-01 T04)
_assert "vbw-docs.md contains '<skill_no_activation>' keyword" \
    grep -q '<skill_no_activation>' ".claude/agents/vbw-docs.md"

# vbw-debugger.md must contain a CMM rationale comment (CMM extension marker preserved)
_assert "vbw-debugger.md contains '<!-- CMM:' rationale marker" \
    grep -q '<!-- CMM:' ".claude/agents/vbw-debugger.md"

# --- Idempotency: snapshot, re-run setup, diff ---

# Capture pre-second-run state of installed agents and settings.
agents_sha_before=$(find .claude/agents -type f -name '*.md' -print0 | sort -z | xargs -0 shasum | shasum | awk '{print $1}')
agents_count_before=$(find .claude/agents -type f -name '*.md' | wc -l | tr -d ' ')
settings_sha_before=$(shasum .claude/settings.json | awk '{print $1}')

echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project second run exited non-zero"
    FAIL=$((FAIL+1))
}

agents_sha_after=$(find .claude/agents -type f -name '*.md' -print0 | sort -z | xargs -0 shasum | shasum | awk '{print $1}')
agents_count_after=$(find .claude/agents -type f -name '*.md' | wc -l | tr -d ' ')
settings_sha_after=$(shasum .claude/settings.json | awk '{print $1}')

_assert "Idempotent: agent file count unchanged on re-run" \
    bash -c "[ \"$agents_count_before\" = \"$agents_count_after\" ]"

_assert "Idempotent: combined agent content hash unchanged on re-run" \
    bash -c "[ \"$agents_sha_before\" = \"$agents_sha_after\" ]"

_assert "Idempotent: settings.json hash unchanged on re-run" \
    bash -c "[ \"$settings_sha_before\" = \"$settings_sha_after\" ]"

# --- Body content survives the second install (no truncation/overwrite regression) ---
_assert "After re-run: vbw-qa.md still contains 'write-verification.sh'" \
    grep -q 'write-verification.sh' ".claude/agents/vbw-qa.md"

_assert "After re-run: vbw-dev.md still contains 'pre_existing_issues'" \
    grep -q 'pre_existing_issues' ".claude/agents/vbw-dev.md"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
