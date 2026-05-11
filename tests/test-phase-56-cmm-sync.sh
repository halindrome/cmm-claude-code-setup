#!/bin/bash
# test-phase-56-cmm-sync.sh — Bundle-install regression for Phase 56 (CMM v0.6.1+101 sync)
# Verifies that setup.sh --project --force installs the four Phase 56-modified surface artifacts
# (rules/cmm-rules.md, README.md derivative content where applicable, setup.sh derivative
# content where applicable, and the three CMM agent overrides) into a scratch project,
# that each carries the body content asserted by Plans 56-01 / 56-02 / 56-03 / 56-04, and that
# re-running setup is idempotent (no duplicate files, byte-stable settings.json hash, content
# hashes unchanged on re-install). Modeled on tests/test-phase-52-bundle-install.sh.
# Usage: bash tests/test-phase-56-cmm-sync.sh
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
SCRATCH=$(mktemp -d -t cmm-phase56-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

cd "$SCRATCH"

# Minimal git repo so setup.sh --project has a project root to anchor to.
git init -q
git commit --allow-empty -q -m "init"

# Run install (non-interactive, skip MCP availability check, force-overwrite any defaults).
echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check --force >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project first run exited non-zero"
    exit 1
}

# --- Phase 56 modified file set is installed ---
# Three CMM agent overrides annotated in Plan 56-04 T1+T2.
for agent in vbw-scout vbw-dev vbw-debugger; do
    _assert ".claude/agents/${agent}.md installed" \
        test -f ".claude/agents/${agent}.md"
done

# rules/cmm-rules.md is bundled into .claude/rules/ by setup.sh (Plan 56-01 modified this file).
_assert ".claude/rules/cmm-rules.md installed" \
    test -f ".claude/rules/cmm-rules.md"

# --- Body-content assertions from Plan 56-01 (cmm-rules.md upstream-behavior keywords) ---

_assert "cmm-rules.md contains 'search_graph' 200-row cap note (Plan 56-01)" \
    grep -qE 'search_graph.*200|200.*rows.*search_graph|200 rows' ".claude/rules/cmm-rules.md"

_assert "cmm-rules.md contains paging guidance ('offset' or 'query_graph')" \
    bash -c "[ \"\$(grep -cE 'offset|query_graph' .claude/rules/cmm-rules.md)\" -ge 2 ]"

_assert "cmm-rules.md contains search_code multi-word regex note (Plan 56-01)" \
    grep -qE 'search_code.*regex|regex.*search_code|multi-word.*regex|auto-converts.*regex' ".claude/rules/cmm-rules.md"

_assert "cmm-rules.md contains list_projects /tmp visibility note (Plan 56-01)" \
    grep -qE 'list_projects.*/tmp|/tmp.*list_projects' ".claude/rules/cmm-rules.md"

# --- Body-content assertions from Plan 56-04 (agent annotation: list_projects /tmp note) ---

for agent in vbw-scout vbw-dev vbw-debugger; do
    _assert "${agent}.md contains list_projects /tmp annotation (Plan 56-04)" \
        grep -qE 'list_projects.*/tmp|/tmp.*list_projects' ".claude/agents/${agent}.md"
done

# --- Frontmatter / hook matchers preserved verbatim (CMM-specific override hooks) ---

for agent in vbw-scout vbw-dev vbw-debugger; do
    _assert "${agent}.md preserves cmm-orient-nudge.sh hook wiring" \
        grep -q 'cmm-orient-nudge.sh' ".claude/agents/${agent}.md"
    _assert "${agent}.md preserves cmm-query-stale-advisory.sh hook wiring" \
        grep -q 'cmm-query-stale-advisory.sh' ".claude/agents/${agent}.md"
    _assert "${agent}.md preserves track-cmm-calls.sh hook wiring" \
        grep -q 'track-cmm-calls.sh' ".claude/agents/${agent}.md"
done

# --- Idempotency: snapshot, re-run setup --force, diff ---

agents_sha_before=$(find .claude/agents -type f -name '*.md' -print0 | sort -z | xargs -0 shasum | shasum | awk '{print $1}')
agents_count_before=$(find .claude/agents -type f -name '*.md' | wc -l | tr -d ' ')
rules_sha_before=$(shasum .claude/rules/cmm-rules.md | awk '{print $1}')
settings_sha_before=$(shasum .claude/settings.json | awk '{print $1}')

echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check --force >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project second run exited non-zero"
    FAIL=$((FAIL+1))
}

agents_sha_after=$(find .claude/agents -type f -name '*.md' -print0 | sort -z | xargs -0 shasum | shasum | awk '{print $1}')
agents_count_after=$(find .claude/agents -type f -name '*.md' | wc -l | tr -d ' ')
rules_sha_after=$(shasum .claude/rules/cmm-rules.md | awk '{print $1}')
settings_sha_after=$(shasum .claude/settings.json | awk '{print $1}')

_assert "Idempotent: agent file count unchanged on --force re-run" \
    bash -c "[ \"$agents_count_before\" = \"$agents_count_after\" ]"

_assert "Idempotent: combined agent content hash unchanged on --force re-run" \
    bash -c "[ \"$agents_sha_before\" = \"$agents_sha_after\" ]"

_assert "Idempotent: cmm-rules.md hash unchanged on --force re-run" \
    bash -c "[ \"$rules_sha_before\" = \"$rules_sha_after\" ]"

_assert "Idempotent: settings.json hash unchanged on --force re-run" \
    bash -c "[ \"$settings_sha_before\" = \"$settings_sha_after\" ]"

# --- Body content survives the second --force install (no truncation/overwrite regression) ---

_assert "After re-run: cmm-rules.md still contains 200-row cap note" \
    grep -qE 'search_graph.*200|200.*rows.*search_graph|200 rows' ".claude/rules/cmm-rules.md"

_assert "After re-run: vbw-dev.md still contains list_projects /tmp annotation" \
    grep -qE 'list_projects.*/tmp|/tmp.*list_projects' ".claude/agents/vbw-dev.md"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
