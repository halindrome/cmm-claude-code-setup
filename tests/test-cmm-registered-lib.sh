#!/bin/bash
# test-cmm-registered-lib.sh — covers hooks/lib/cmm-registered.sh and asserts that
# EVERY hook with an availability cascade routes through it.
#
# Two defects motivated this file, both of which shipped because each hook
# hand-rolled its own probe:
#   1. cmm-grep-nudge.sh has TWO cascades; a fix applied to one missed the other,
#      leaving Bash navigation fail-open while Grep blocked.
#   2. A substring match on 'codebase-memory-mcp' treated a permissions allowlist
#      (or a DENY rule) as registration — fail-closed, with no escape.
#
# Run: bash tests/test-cmm-registered-lib.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LIB="$REPO_ROOT/hooks/lib/cmm-registered.sh"

PASS=0; FAIL=0
_chk() { if eval "$2"; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }

# shellcheck disable=SC1090
source "$LIB"

T=$(mktemp -d)
export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$T/home/.config/claude-code"
mkdir -p "$CLAUDE_CONFIG_DIR" "$T/proj" "$HOME/.claude"

echo "--- registration is an mcpServers key, not a substring ---"
_chk "clean tree -> not registered" '! cmm_is_registered "$T/proj"'

echo '{"permissions":{"allow":["mcp__codebase-memory-mcp__search_graph"]}}' \
    > "$CLAUDE_CONFIG_DIR/settings.json"
_chk "allowlist entry alone -> NOT registered" '! cmm_is_registered "$T/proj"'

echo '{"permissions":{"deny":["mcp__codebase-memory-mcp__search_code"]}}' \
    > "$CLAUDE_CONFIG_DIR/settings.json"
_chk "DENY rule alone -> NOT registered (must never fail closed)" '! cmm_is_registered "$T/proj"'

echo "--- each location setup.sh probes is honoured ---"
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$T/proj/.mcp.json"
_chk "project .mcp.json -> registered" 'cmm_is_registered "$T/proj"'
rm -f "$T/proj/.mcp.json"

echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$CLAUDE_CONFIG_DIR/settings.json"
_chk "config settings.json -> registered" 'cmm_is_registered "$T/proj"'
echo '{}' > "$CLAUDE_CONFIG_DIR/settings.json"

echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
_chk "config .claude.json -> registered (user-scope mcp add)" 'cmm_is_registered "$T/proj"'
rm -f "$CLAUDE_CONFIG_DIR/.claude.json"

echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$HOME/.claude.json"
_chk "~/.claude.json -> registered" 'cmm_is_registered "$T/proj"'
rm -f "$HOME/.claude.json"

echo "--- malformed input must not crash or fail closed ---"
echo 'not json {{{' > "$CLAUDE_CONFIG_DIR/settings.json"
_chk "unparseable settings.json -> not registered, no crash" '! cmm_is_registered "$T/proj"'
echo '{"mcpServers":"a string"}' > "$CLAUDE_CONFIG_DIR/settings.json"
_chk "mcpServers of wrong type -> not registered" '! cmm_is_registered "$T/proj"'
echo '{}' > "$CLAUDE_CONFIG_DIR/settings.json"
_chk "empty repo_root argument -> not registered, no crash" '! cmm_is_registered ""'

echo "--- no hook hand-rolls its own cascade any more ---"
# This is what stops the two cascades in one file from drifting apart again.
for h in hooks/project/index-root-gate.sh hooks/project/ctx-execute-cmm-nudge.sh \
         hooks/project/grep-cmm-gate.sh hooks/global/cmm-grep-nudge.sh \
         hooks/global/cmm-nudge.sh; do
  _chk "$(basename "$h") sources the shared lib" \
       'grep -q "cmm-registered.sh" "$REPO_ROOT/'"$h"'"'
  _chk "$(basename "$h") has no substring probe left" \
       '! grep -qE "grep -q .codebase-memory-mcp." "$REPO_ROOT/'"$h"'"'
done

# Every CMM_FOUND-style variable must be set from the shared helper, so a file
# with two cascades cannot have one armed and the other not.
_chk "cmm-grep-nudge.sh routes BOTH cascades through the helper" \
     '[ "$(grep -c "cmm_is_registered" "$REPO_ROOT/hooks/global/cmm-grep-nudge.sh")" -ge 2 ]'

rm -rf "$T"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
