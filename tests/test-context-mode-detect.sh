#!/bin/bash
# Functional test for hooks/lib/context-mode-detect.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
source "$REPO_ROOT/hooks/lib/context-mode-detect.sh"

PASS=0; FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1));
  else echo "  FAIL  $1 (expected $2, got $3)"; FAIL=$((FAIL+1)); fi
}

T=$(mktemp -d)
export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$T/home/.config/claude-code"
mkdir -p "$CLAUDE_CONFIG_DIR/plugins" "$T/repo/.claude" "$HOME/.claude"
unset CLAUDE_PLUGIN_ROOT

reg() { cat > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"; }

echo "== 1. registry installPath does NOT resolve (devcontainer skew) =="
reg <<JSON
{"plugins":{"context-mode@context-mode":[{"installPath":"/home/vscode/.config/claude-code/plugins/cache/context-mode/context-mode/1.0.169"}]},
 "enabledPlugins":{"context-mode@context-mode":true}}
JSON
# make the cache dir exist on THIS filesystem — the old probe's false positive
mkdir -p "$CLAUDE_CONFIG_DIR/plugins/cache/context-mode/context-mode/1.0.169/.claude-plugin"
echo '{"name":"context-mode"}' > "$CLAUDE_CONFIG_DIR/plugins/cache/context-mode/context-mode/1.0.169/.claude-plugin/plugin.json"
detect_context_mode "$T/repo"
check "unresolvable installPath -> not installed" 0 "$CONTEXT_MODE_INSTALLED"

echo "== 2. registry installPath resolves =="
reg <<JSON
{"plugins":{"context-mode@context-mode":[{"installPath":"$CLAUDE_CONFIG_DIR/plugins/cache/context-mode/context-mode/1.0.169"}]},
 "enabledPlugins":{"context-mode@context-mode":true}}
JSON
detect_context_mode "$T/repo"
check "resolvable installPath -> installed" 1 "$CONTEXT_MODE_INSTALLED"

echo "== 3. explicit opt-out is honored =="
reg <<JSON
{"plugins":{"context-mode@context-mode":[{"installPath":"$CLAUDE_CONFIG_DIR/plugins/cache/context-mode/context-mode/1.0.169"}]},
 "enabledPlugins":{"context-mode@context-mode":false}}
JSON
detect_context_mode "$T/repo"
check "enabledPlugins=false -> not installed" 0 "$CONTEXT_MODE_INSTALLED"

echo "== 4. no registry, classic mcpServers registration =="
rm -f "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
echo '{"mcpServers":{"context-mode":{"command":"node"}}}' > "$CLAUDE_CONFIG_DIR/settings.json"
detect_context_mode "$T/repo"
check "mcpServers entry -> installed" 1 "$CONTEXT_MODE_INSTALLED"

echo "== 5. stale session DB no longer latches detection on =="
rm -f "$CLAUDE_CONFIG_DIR/settings.json"
touch "$T/repo/.claude/context-mode.db"
detect_context_mode "$T/repo"
check "orphan context-mode.db -> not installed" 0 "$CONTEXT_MODE_INSTALLED"

echo "== 6. cache invalidates when the registry changes =="
CACHE="$T/cache"
echo '{"mcpServers":{"context-mode":{"command":"node"}}}' > "$CLAUDE_CONFIG_DIR/settings.json"
detect_context_mode "$T/repo" "$CACHE"
check "primed cache -> installed" 1 "$CONTEXT_MODE_INSTALLED"
sleep 1
rm -f "$CLAUDE_CONFIG_DIR/settings.json"
touch "$CLAUDE_CONFIG_DIR/settings.json"   # newer than cache, now empty
detect_context_mode "$T/repo" "$CACHE"
check "registry changed -> cache recomputed" 0 "$CONTEXT_MODE_INSTALLED"

rm -rf "$T"
echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
