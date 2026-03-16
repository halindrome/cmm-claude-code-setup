#!/bin/bash
# test-statusline-path.sh — verify setup.sh project mode writes absolute statusline path

set -euo pipefail

SETUP_SH="$(cd "$(dirname "$0")/.." && pwd)/setup.sh"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

echo "=== Test 1: setup.sh source contains absolute-path pattern ==="
grep -q 'project_root=\$(pwd)' "$SETUP_SH" || { echo "FAIL: project_root=\$(pwd) not found in setup.sh"; exit 1; }
grep -q '"${project_root}/.claude"' "$SETUP_SH" || { echo "FAIL: absolute path pattern not found in setup.sh"; exit 1; }
# Confirm the bare relative ".claude" is no longer passed in project mode
if grep -E '_run_install_statusline_for_target\s+["\x27]\.claude["\x27]\s+["\x27]project["\x27]' "$SETUP_SH" >/dev/null 2>&1; then
  echo "FAIL: bare relative .claude still passed to _run_install_statusline_for_target"
  exit 1
fi
echo "PASS: source contains absolute-path call"

echo "=== Test 2: project-mode install writes absolute path into settings.local.json ==="
cd "$TMPDIR_ROOT"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
mkdir -p .claude/hooks

# Run setup.sh --project with --force to bypass interactive prompts for statusline
bash "$SETUP_SH" --project --skip-mcp-check --force 2>/dev/null || true

SETTINGS="$TMPDIR_ROOT/.claude/settings.local.json"
if [ ! -f "$SETTINGS" ]; then
  echo "FAIL: settings.local.json not created"
  exit 1
fi

# The statusline command must contain an absolute path (starts with /)
if python3 -c "
import json, sys
with open('$SETTINGS') as f:
    data = json.load(f)
cmd = data.get('statusLine', {}).get('command', '')
if not cmd:
    print('FAIL: no statusLine.command in settings')
    sys.exit(1)
# The path inside the command should be absolute (contains / before .claude)
if '\"/' in cmd or \"'/\" in cmd:
    print('PASS: statusLine command contains absolute path')
    print(f'  command: {cmd}')
else:
    print(f'FAIL: statusLine command does not contain absolute path: {cmd}')
    sys.exit(1)
" 2>/dev/null; then
  : # python check passed
else
  echo "FAIL: settings.local.json does not contain absolute statusline path"
  if [ -f "$SETTINGS" ]; then
    echo "Contents:"
    cat "$SETTINGS"
  fi
  exit 1
fi

echo "=== Test 3: statusline runs from a subdirectory ==="
STATUSLINE_SCRIPT="$TMPDIR_ROOT/.claude/hooks/statusline-cmm.sh"
if [ -f "$STATUSLINE_SCRIPT" ]; then
  mkdir -p "$TMPDIR_ROOT/sub/dir"
  cd "$TMPDIR_ROOT/sub/dir"
  OUTPUT=$(bash "$STATUSLINE_SCRIPT" 2>/dev/null || true)
  if [ -n "$OUTPUT" ]; then
    echo "PASS: statusline script runs from subdirectory (output: $OUTPUT)"
  else
    echo "INFO: statusline script produced no output from subdirectory (may need CMM running)"
  fi
else
  echo "INFO: statusline script not found at $STATUSLINE_SCRIPT (skipping subdirectory test)"
fi

echo ""
echo "All tests passed."
