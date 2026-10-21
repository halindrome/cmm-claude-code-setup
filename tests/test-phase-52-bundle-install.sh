#!/bin/bash
# test-phase-52-bundle-install.sh — Integration smoke test for Phase 52 agent bundle install
#
# Phase 66 architectural update: agents/vbw-*.md are no longer verbatim-copied by
# setup.sh --project. Instead, setup.sh registers agent-override-generate.sh as a
# SessionStart hook, which merges VBW base bodies with our delta files at runtime.
# In a scratch env without a live VBW install, the generate hook runs but produces
# no output (fail-open). This test therefore verifies:
#   - The generate hook is installed at .claude/hooks/agent-override-generate.sh
#   - The generate hook is registered under SessionStart in .claude/settings.json
#   - .claude/agents/ directory is created by setup.sh
#   - Idempotency: settings.json hash and hook file hash unchanged on re-run
#
# The original body-content assertions (write-verification.sh, pre_existing_issues,
# skill_no_activation, CMM rationale) are now covered by:
#   - tests/test-phase-66-delta-format.sh (source delta files)
#   - tests/test-phase-66-generate.sh (generated output)
#
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

# VBW agent-override install is gated on VBW being installed as a plugin. Set up a
# fake marketplace VBW via CLAUDE_CONFIG_DIR so this test (which verifies the VBW
# override-install path) is deterministic regardless of the machine's VBW state.
FAKE_CFG="$SCRATCH/claude-config"
FAKE_VBW="$FAKE_CFG/plugins/cache/vbw-marketplace/vbw/1.99.0"
mkdir -p "$FAKE_VBW/agents" "$FAKE_CFG/plugins"
cat >"$FAKE_CFG/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"vbw@vbw-marketplace":[{"installPath":"$FAKE_VBW","version":"1.99.0","scope":"user"}]},"enabledPlugins":{"vbw@vbw-marketplace":true}}
JSON
export CLAUDE_CONFIG_DIR="$FAKE_CFG"

# Run install (non-interactive, skip MCP availability check).
echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project first run exited non-zero"
    exit 1
}

# --- Phase 66 arch: generate hook installed, .claude/agents/ dir created ---

# The generate hook must be installed (setup.sh copies hooks/project/*.sh)
_assert "agent-override-generate.sh installed at .claude/hooks/" \
    test -f ".claude/hooks/agent-override-generate.sh"

# The generate hook must be registered under SessionStart in settings.json
_assert "agent-override-generate.sh registered in settings.json (SessionStart)" \
    grep -q 'agent-override-generate' ".claude/settings.json"

# The .claude/agents/ directory must exist (setup.sh creates it)
_assert ".claude/agents/ directory created by setup.sh" \
    test -d ".claude/agents"

# vbw-source.sh lib must be installed (required by the generate hook at runtime)
_assert "vbw-source.sh installed at .claude/hooks/lib/" \
    test -f ".claude/hooks/lib/vbw-source.sh"

# --- Idempotency: snapshot, re-run setup, diff ---

# Capture pre-second-run state
hook_sha_before=$(shasum ".claude/hooks/agent-override-generate.sh" | awk '{print $1}')
settings_sha_before=$(shasum .claude/settings.json | awk '{print $1}')

echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || {
    echo "FAIL: setup.sh --project second run exited non-zero"
    FAIL=$((FAIL+1))
}

hook_sha_after=$(shasum ".claude/hooks/agent-override-generate.sh" | awk '{print $1}')
settings_sha_after=$(shasum .claude/settings.json | awk '{print $1}')

_assert "Idempotent: agent-override-generate.sh hash unchanged on re-run" \
    bash -c "[ \"$hook_sha_before\" = \"$hook_sha_after\" ]"

_assert "Idempotent: settings.json hash unchanged on re-run" \
    bash -c "[ \"$settings_sha_before\" = \"$settings_sha_after\" ]"

# --- After re-run: hook still registered ---
_assert "After re-run: agent-override-generate.sh still registered in settings.json" \
    grep -q 'agent-override-generate' ".claude/settings.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
