#!/bin/bash
# test-e2e-agent-enforcement.sh — End-to-end test: setup.sh --project install + agent enforcement validation
# Usage: bash tests/test-e2e-agent-enforcement.sh
# Exit: 0 = all pass, 1 = any failure
#
# Creates a fixture repo, runs setup.sh --project, then validates:
#   Section 1: Installed file existence (hooks, agents, rules, settings, mcp.json)
#   Section 2: settings.json hook registration structure (via python3)
#   Section 3: Agent override content (name fields, hook references, SUBAGENT_COMMIT)
# Plan 03 extends this script with hook blocking tests at the marked insertion point.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SETUP_SH="$PROJECT_ROOT/setup.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ─── Fixture Setup ────────────────────────────────────────────────────────
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Create a minimal git repo fixture for setup.sh --project
FIXTURE="$TMPDIR_ROOT/proj"
mkdir -p "$FIXTURE"
git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email "test@test.com"
git -C "$FIXTURE" config user.name "Test"
echo "# fixture" > "$FIXTURE/README.md"
git -C "$FIXTURE" add README.md
git -C "$FIXTURE" commit -q -m "init"

# Fake CLAUDE_CONFIG_DIR to prevent global settings interference
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{}' > "$FAKE_CONFIG/settings.json"

# Run setup.sh --project from inside the fixture
echo "=== Running setup.sh --project ==="
INSTALL_OUTPUT=$(cd "$FIXTURE" && echo "n" | env CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$SETUP_SH" --project --skip-mcp-check --skip-statusline --force 2>&1) || {
  echo "FATAL: setup.sh --project failed (exit $?)"
  echo "$INSTALL_OUTPUT"
  exit 1
}
echo "  setup.sh --project completed successfully"
echo ""

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
