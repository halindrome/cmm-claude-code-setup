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
# Both cmm-rules and ctx-rules are emitted in one block so the model does not
# skip a second Skill() call from a separate hook turn (multi-block skip observed
# in Phase 61 field test: 8/10 cmm-rules activations, 0/10 ctx-rules activations).
# Concrete tool-preference mandate (not just a Skill nudge): prefer CMM graph
# tools over Read/grep for code, and route large output through ctx_* — the soft
# "invoke Skill" advisory alone was empirically ignored by subagents whose own
# prompts told them to grep/read. NOTE: this injection IS delivered reliably
# (~2,210 times per 30 days, measured 2026-09-03) — delivery is not the problem.
# Adoption is: 52% of gated subagent transcripts still make zero CMM calls, and a
# blocked Grep becomes a Read more often than a search_graph. So this hook is a
# floor; the durable lever remains baking rules/cmm-agent-preamble.md into the
# subagent's PROMPT.
MANDATE="Prefer CMM graph tools (search_graph / get_code_snippet / trace_path / get_architecture) over Read/grep for code exploration; cite definition sites from get_code_snippet, not grep hits. Route large diffs, whole-file reads, and command output through ctx_execute / ctx_batch_execute / ctx_search to keep bytes out of context."
if [ ! -f "$CMM_SENTINEL" ] || grep -q '^stale$' "$CMM_SENTINEL"; then
    ADVISORY="⚠ CMM index is stale. Call index_repository before graph tools. $MANDATE Invoke Skill('cmm-rules') via the Skill tool now, then Invoke Skill('ctx-rules') via the Skill tool now."
else
    ADVISORY="CMM index is ready. $MANDATE Invoke Skill('cmm-rules') via the Skill tool now, then Invoke Skill('ctx-rules') via the Skill tool now."
fi

# JSON-encode via python3 json.dumps so embedded quotes, backslashes, and
# control characters survive correctly. The previous sed-based escape only
# handled bare double-quotes and could emit invalid JSON for richer payloads.
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":sys.argv[1]}}))' \
    "$ADVISORY"

exit 0
