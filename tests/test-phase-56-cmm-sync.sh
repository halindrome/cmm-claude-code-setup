#!/bin/bash
# test-phase-56-cmm-sync.sh — Bundle-install regression for Phase 56 (CMM v0.6.1+101 sync)
#
# Phase 66 architectural update: agents/vbw-*.md are now delta-only source files.
# The list_projects /tmp annotation and hook-wiring assertions that previously checked
# installed .claude/agents/*.md are no longer valid post-install (the generate hook
# creates merged files at SessionStart, not at setup time). Those assertions have been
# updated to check the DELTA SOURCE FILES (agents/vbw-*.md in the repo) instead.
#
# Idempotency: setup.sh --force re-run still verified for rules/ and settings.json.
# Agent content idempotency is now covered by test-phase-66-generate.sh (SHA-based).
#
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

# The agent-override-generate.sh install is gated on VBW being installed as a
# plugin. Fake a marketplace VBW via CLAUDE_CONFIG_DIR so this assertion is
# deterministic regardless of the machine's VBW state.
FAKE_CFG="$SCRATCH/claude-config"
FAKE_VBW="$FAKE_CFG/plugins/cache/vbw-marketplace/vbw/1.99.0"
mkdir -p "$FAKE_VBW/agents" "$FAKE_CFG/plugins"
cat >"$FAKE_CFG/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"vbw@vbw-marketplace":[{"installPath":"$FAKE_VBW","version":"1.99.0","scope":"user"}]},"enabledPlugins":{"vbw@vbw-marketplace":true}}
JSON
export CLAUDE_CONFIG_DIR="$FAKE_CFG"

# Run install (non-interactive, skip MCP availability check, force-overwrite any defaults).
echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check --force >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project first run exited non-zero"
    exit 1
}

# --- Phase 56 modified file set is installed ---
# rules/cmm-rules.md is bundled into .claude/rules/ by setup.sh (Plan 56-01 modified this file).
_assert ".claude/rules/cmm-rules.md installed" \
    test -f ".claude/rules/cmm-rules.md"

# The generate hook must be installed (replaces verbatim agent copy from setup.sh).
_assert "agent-override-generate.sh installed (Phase 66 arch replaces verbatim copy)" \
    test -f ".claude/hooks/agent-override-generate.sh"

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
# Phase 66: these annotations live in agents/vbw-*.md DELTA SOURCE files (cmm-delta fences).
# We assert on the repo source files (not the generated installed files, which require VBW).

for agent in vbw-scout vbw-dev vbw-debugger; do
    _assert "${agent}.md delta source contains list_projects /tmp annotation (Plan 56-04)" \
        grep -qE 'list_projects.*/tmp|/tmp.*list_projects' "$REPO_ROOT/agents/${agent}.md"
done

# --- Frontmatter / hook matchers in delta SOURCE files (CMM-specific override hooks) ---
# Phase 66: hooks: live in delta frontmatter of agents/vbw-*.md source files.

for agent in vbw-scout vbw-dev vbw-debugger; do
    _assert "${agent}.md delta source has cmm-orient-nudge.sh hook wiring" \
        grep -q 'cmm-orient-nudge.sh' "$REPO_ROOT/agents/${agent}.md"
    _assert "${agent}.md delta source has cmm-query-stale-advisory.sh hook wiring" \
        grep -q 'cmm-query-stale-advisory.sh' "$REPO_ROOT/agents/${agent}.md"
    _assert "${agent}.md delta source has track-cmm-calls.sh hook wiring" \
        grep -q 'track-cmm-calls.sh' "$REPO_ROOT/agents/${agent}.md"
done

# --- Idempotency: snapshot, re-run setup --force, diff ---

rules_sha_before=$(shasum .claude/rules/cmm-rules.md | awk '{print $1}')
settings_sha_before=$(shasum .claude/settings.json | awk '{print $1}')
hook_sha_before=$(shasum .claude/hooks/agent-override-generate.sh | awk '{print $1}')

echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check --force >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project second run exited non-zero"
    FAIL=$((FAIL+1))
}

rules_sha_after=$(shasum .claude/rules/cmm-rules.md | awk '{print $1}')
settings_sha_after=$(shasum .claude/settings.json | awk '{print $1}')
hook_sha_after=$(shasum .claude/hooks/agent-override-generate.sh | awk '{print $1}')

_assert "Idempotent: cmm-rules.md hash unchanged on --force re-run" \
    bash -c "[ \"$rules_sha_before\" = \"$rules_sha_after\" ]"

_assert "Idempotent: settings.json hash unchanged on --force re-run" \
    bash -c "[ \"$settings_sha_before\" = \"$settings_sha_after\" ]"

_assert "Idempotent: agent-override-generate.sh hash unchanged on --force re-run" \
    bash -c "[ \"$hook_sha_before\" = \"$hook_sha_after\" ]"

# --- Content survives the second --force install ---

_assert "After re-run: cmm-rules.md still contains 200-row cap note" \
    grep -qE 'search_graph.*200|200.*rows.*search_graph|200 rows' ".claude/rules/cmm-rules.md"

_assert "After re-run: agent-override-generate.sh still registered in settings.json" \
    grep -q 'agent-override-generate' ".claude/settings.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
