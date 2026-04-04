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

# ─── Section 1: Installed File Existence ─────────────────────────────────
echo "=== Section 1: Installed File Existence ==="

# Hook files expected in .claude/hooks/ (13 from hooks/project/ + cmm-nudge.sh from hooks/global/)
EXPECTED_HOOKS=(
  session-gate.sh
  agent-cmm-gate.sh
  ctx-execute-enforcer.sh
  cmm-sentinel-writer.sh
  cmm-session-start.sh
  subagent-cmm-startup.sh
  reindex-after-commit.sh
  track-cmm-calls.sh
  cmm-query-stale-advisory.sh
  context-mode-event-logger.sh
  context-mode-sentinel-writer.sh
  context-mode-pre-compact.sh
  track-hook-blocks.sh
  cmm-nudge.sh
)

for hook in "${EXPECTED_HOOKS[@]}"; do
  if [ -f "$FIXTURE/.claude/hooks/$hook" ]; then
    pass "hook exists: $hook"
  else
    fail "hook missing: $hook"
  fi
done

# cmm-nudge.sh specifically — validates global hook was copied to project hooks dir
if [ -f "$FIXTURE/.claude/hooks/cmm-nudge.sh" ]; then
  pass "cmm-nudge.sh copied from global hooks"
else
  fail "cmm-nudge.sh not copied from global hooks"
fi

# Agent override files in .claude/agents/
EXPECTED_AGENTS=(
  vbw-dev.md
  vbw-debugger.md
  vbw-qa.md
  vbw-scout.md
  vbw-architect.md
  vbw-lead.md
  vbw-docs.md
)

for agent in "${EXPECTED_AGENTS[@]}"; do
  if [ -f "$FIXTURE/.claude/agents/$agent" ]; then
    pass "agent exists: $agent"
  else
    fail "agent missing: $agent"
  fi
done

# Rules files in .claude/rules/
EXPECTED_RULES=(
  project-settings-example.json
  mcp-example.json
  allowed-tools.txt
  global-claude-md.md
)

for rule in "${EXPECTED_RULES[@]}"; do
  if [ -f "$FIXTURE/.claude/rules/$rule" ]; then
    pass "rule exists: $rule"
  else
    fail "rule missing: $rule"
  fi
done

# .mcp.json exists and contains codebase-memory-mcp
if [ -f "$FIXTURE/.mcp.json" ]; then
  pass ".mcp.json exists"
  if grep -q "codebase-memory-mcp" "$FIXTURE/.mcp.json"; then
    pass ".mcp.json contains codebase-memory-mcp"
  else
    fail ".mcp.json missing codebase-memory-mcp"
  fi
else
  fail ".mcp.json missing"
fi

# .claude/settings.json exists
if [ -f "$FIXTURE/.claude/settings.json" ]; then
  pass "settings.json exists"
else
  fail "settings.json missing"
fi

echo ""

# ─── Section 2: settings.json Hook Registration Validation ───────────────
echo "=== Section 2: settings.json Hook Registration ==="

# Resolve the fixture's canonical path for absolute path checks
FIXTURE_CANONICAL=$(cd "$FIXTURE" && pwd -P)

# Validate settings.json structure using python3
# Write results to temp file to avoid subshell counter loss from pipes
SETTINGS_RESULTS="$TMPDIR_ROOT/settings-results.txt"

python3 -c "
import json, sys
with open('$FIXTURE/.claude/settings.json') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
if 'hooks' not in data:
    print('NO_HOOKS')
    sys.exit(0)
for htype in ['SessionStart', 'PreToolUse', 'PostToolUse', 'SubagentStart']:
    if htype in hooks:
        print(f'HAS:{htype}')
    else:
        print(f'MISSING:{htype}')
" > "$SETTINGS_RESULTS"

while IFS= read -r line; do
  case "$line" in
    NO_HOOKS) fail "settings.json has no hooks key" ;;
    HAS:*)    pass "settings.json has ${line#HAS:} section" ;;
    MISSING:*) fail "settings.json missing ${line#MISSING:} section" ;;
  esac
done < "$SETTINGS_RESULTS"

# Validate specific hook registrations
python3 -c "
import json, sys
with open('$FIXTURE/.claude/settings.json') as f:
    data = json.load(f)
hooks = data.get('hooks', {})

def find_commands(hook_type):
    groups = hooks.get(hook_type, [])
    cmds = []
    for g in groups:
        for h in g.get('hooks', []):
            cmds.append(h.get('command', ''))
    return cmds

# session-gate.sh in PreToolUse
pre_cmds = find_commands('PreToolUse')
if any('session-gate.sh' in c for c in pre_cmds):
    print('FOUND:session-gate.sh in PreToolUse')
else:
    print('NOTFOUND:session-gate.sh in PreToolUse')

# cmm-session-start.sh in SessionStart
ss_cmds = find_commands('SessionStart')
if any('cmm-session-start.sh' in c for c in ss_cmds):
    print('FOUND:cmm-session-start.sh in SessionStart')
else:
    print('NOTFOUND:cmm-session-start.sh in SessionStart')

# subagent-cmm-startup.sh in SubagentStart
sa_cmds = find_commands('SubagentStart')
if any('subagent-cmm-startup.sh' in c for c in sa_cmds):
    print('FOUND:subagent-cmm-startup.sh in SubagentStart')
else:
    print('NOTFOUND:subagent-cmm-startup.sh in SubagentStart')

# All hook commands use absolute paths containing fixture dir
fixture_path = '$FIXTURE_CANONICAL'
all_cmds = []
for htype in hooks:
    all_cmds.extend(find_commands(htype))
non_abs = [c for c in all_cmds if c and fixture_path not in c]
if non_abs:
    print('BADPATH:' + '|'.join(non_abs[:3]))
else:
    print('ABSPATH:all hook commands use absolute paths')
" > "$SETTINGS_RESULTS"

while IFS= read -r line; do
  case "$line" in
    FOUND:*)    pass "${line#FOUND:}" ;;
    NOTFOUND:*) fail "${line#NOTFOUND:}" ;;
    ABSPATH:*)  pass "${line#ABSPATH:}" ;;
    BADPATH:*)  fail "hook commands with non-absolute paths: ${line#BADPATH:}" ;;
  esac
done < "$SETTINGS_RESULTS"

echo ""

# ─── Section 3: Agent Override Content Validation ────────────────────────
echo "=== Section 3: Agent Override Content ==="

# All 7 agents with correct name: field
AGENT_NAMES=(vbw-dev vbw-debugger vbw-qa vbw-scout vbw-architect vbw-lead vbw-docs)

for agent in "${AGENT_NAMES[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue

  # Correct name: field
  if grep -q "^name: ${agent}$" "$file"; then
    pass "$agent has correct name: field"
  else
    fail "$agent missing or incorrect name: field"
  fi

  # cmm-nudge.sh reference (all agents should have it)
  if grep -q "cmm-nudge.sh" "$file"; then
    pass "$agent has cmm-nudge.sh reference"
  else
    fail "$agent missing cmm-nudge.sh reference"
  fi
done

# Agents WITH Bash access should have ctx-execute-enforcer.sh
BASH_AGENTS=(vbw-dev vbw-debugger vbw-qa vbw-lead vbw-docs)
for agent in "${BASH_AGENTS[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  if grep -q "ctx-execute-enforcer.sh" "$file"; then
    pass "$agent has ctx-execute-enforcer.sh (has Bash access)"
  else
    fail "$agent missing ctx-execute-enforcer.sh (should have it — has Bash access)"
  fi
done

# Agents WITHOUT Bash access should NOT have ctx-execute-enforcer.sh
NO_BASH_AGENTS=(vbw-scout vbw-architect)
for agent in "${NO_BASH_AGENTS[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  if grep -q "ctx-execute-enforcer.sh" "$file"; then
    fail "$agent has ctx-execute-enforcer.sh (should NOT — no Bash access)"
  else
    pass "$agent correctly lacks ctx-execute-enforcer.sh (no Bash access)"
  fi
done

# dev and debugger have SUBAGENT_COMMIT=1
COMMIT_AGENTS=(vbw-dev vbw-debugger)
for agent in "${COMMIT_AGENTS[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  if grep -q "SUBAGENT_COMMIT" "$file"; then
    pass "$agent has SUBAGENT_COMMIT marker"
  else
    fail "$agent missing SUBAGENT_COMMIT marker"
  fi
done

# qa, scout, architect, lead, docs should NOT have SUBAGENT_COMMIT
NO_COMMIT_AGENTS=(vbw-qa vbw-scout vbw-architect vbw-lead vbw-docs)
for agent in "${NO_COMMIT_AGENTS[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  if grep -q "SUBAGENT_COMMIT" "$file"; then
    fail "$agent has SUBAGENT_COMMIT (should NOT)"
  else
    pass "$agent correctly lacks SUBAGENT_COMMIT"
  fi
done

# All hook commands in agent frontmatter use project-relative paths (bash .claude/hooks/)
for agent in "${AGENT_NAMES[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  # Check for absolute paths in hook commands — should not exist
  if grep -E 'command:.*(/Users|/home|/tmp).*\.claude/hooks/' "$file" >/dev/null 2>&1; then
    fail "$agent agent has absolute paths in hook commands"
  else
    pass "$agent agent uses project-relative hook paths"
  fi
done

echo ""

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
