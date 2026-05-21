#!/bin/bash
# subagent-cmm-startup.sh — SubagentStart hook (CMM state context injection)
# Fires in the PARENT session when a VBW subagent starts. Injects CMM index state
# into the subagent's context via additionalContext JSON output so the agent knows
# whether to call index_repository before querying the graph.
#
# Install: cp hooks/project/subagent-cmm-startup.sh .claude/hooks/ && chmod +x .claude/hooks/subagent-cmm-startup.sh
# Register in .claude/settings.json under SubagentStart (see rules/project-settings-example.json)
# Matcher: * (all subagents)

# --- Project root detection (shared library with /tmp cache) ---
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
if [ -f "$_LIB_DIR/project-root.sh" ]; then
  source "$_LIB_DIR/project-root.sh"
else
  # Fallback: inline detection (pre-optimization installs)
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$PROJECT_ROOT" ]; then
      _WALK="$PROJECT_ROOT"
      while true; do
          _PARENT="$(git -C "$_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
          [ -z "$_PARENT" ] && break
          _WALK="$_PARENT"
      done
      PROJECT_ROOT="$_WALK"
  fi
  if [ -z "$PROJECT_ROOT" ]; then
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
      PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
  fi
  if [ -n "$PROJECT_ROOT" ]; then
      _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
      _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
      [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
      [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
      if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
          _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
          [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
      fi
  fi
  PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
  CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"
fi

# --- Context Injection ---
# Inject CMM index state into the subagent via additionalContext JSON.
# SubagentStart hooks output: {"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": "..."}}
# Always exit 0 — this hook is advisory only, never blocking.
if [ ! -f "$CMM_SENTINEL" ] || grep -q '^stale$' "$CMM_SENTINEL"; then
    ADVISORY="CMM index is stale. Consult skill \`cmm-rules\` for orient-first pattern; run index_repository first."
else
    ADVISORY="CMM graph is indexed. Consult skill \`cmm-rules\` before reading source files."
fi

# JSON-encode via python3 json.dumps so embedded quotes, backslashes, and
# control characters survive correctly. The previous sed-based escape only
# handled bare double-quotes and could emit invalid JSON for richer payloads.
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":sys.argv[1]}}))' \
    "$ADVISORY"

exit 0
