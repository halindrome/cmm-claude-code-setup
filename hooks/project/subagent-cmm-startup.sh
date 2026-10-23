#!/bin/bash
# subagent-cmm-startup.sh — SubagentStart hook (CMM/ctx guidance injection)
# Fires in the PARENT session when a subagent starts. Injects concrete CMM and
# Context Mode usage guidance (with this repo's project= value) into the
# subagent's context via additionalContext JSON output.
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
  CONTEXT_MODE_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"
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
#
# Guidance only — never index state. A fresh subagent has no prior leanings, so
# the injection must not teach any: no warning glyphs, no "stale", no
# "building", no named fallback (grep) for it to reach for. The old
# "⚠ CMM index is stale. Call index_repository before graph tools." put a step
# in front of CMM and none in front of grep, and a subagent took grep (observed
# in liverpool-cleanup, 2026-10-23). Index freshness is the hooks' job:
# cmm-session-start.sh refreshes the index in the background and
# agent-cmm-gate.sh holds Agent spawns until that refresh finishes. Telling the
# agent "first-time index is building" was considered and rejected for the same
# reason — it invites the agent to route around CMM while it waits.
#
# project= is filled in because a subagent cannot derive it, and a failed first
# CMM call is where agents abandon the graph. Derivation matches
# reindex-after-commit.sh (strip leading /, every / -> -).
_CMM_PROJECT="${PROJECT_ROOT#/}"
_CMM_PROJECT="${_CMM_PROJECT//\//-}"
ADVISORY="This repository is indexed in codebase-memory-mcp (CMM); use it for all code navigation.
Pass project=\"${_CMM_PROJECT}\" on every CMM call below (required; it is not inferred).
- Find a function/class/module by name: search_graph(project, name_pattern=\"...\")
- A symbol's source: get_code_snippet(project, qualified_name=\"...\")
- Who calls X / what X calls: trace_path(project, function_name=\"...\", direction=\"inbound\" | \"outbound\" | \"both\")
- Orient in an unfamiliar area: get_architecture(project)
- Literal text (strings, error messages, TODOs): search_code(project, pattern=\"...\")
Start with get_architecture or search_graph, and cite definition sites from these results.
Use Read for files you are about to edit and for non-code files (config, JSON, Markdown)."
if [ -f "$CONTEXT_MODE_SENTINEL" ]; then
    ADVISORY="$ADVISORY
For command output, test runs, diffs and multi-file scans, use ctx_execute / ctx_batch_execute with intent=\"<your question>\", and call ctx_search before re-running anything."
fi
ADVISORY="$ADVISORY
If you change code and need the graph to reflect it, call index_repository(repo_path=\"${PROJECT_ROOT}\"); it is incremental and takes seconds.
Invoke Skill('cmm-rules') via the Skill tool now, then Invoke Skill('ctx-rules') via the Skill tool now."

# JSON-encode via python3 json.dumps so embedded quotes, backslashes, and
# control characters survive correctly. The previous sed-based escape only
# handled bare double-quotes and could emit invalid JSON for richer payloads.
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":sys.argv[1]}}))' \
    "$ADVISORY"

exit 0
