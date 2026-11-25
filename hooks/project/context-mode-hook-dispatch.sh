#!/bin/bash
# context-mode-hook-dispatch.sh — dispatch a Claude Code hook event to context-mode
#
# Why this exists:
#   `npx -y context-mode@latest hook claude-code <event>` is NOT safe under
#   concurrent invocation. With many tool calls firing PreToolUse+PostToolUse
#   in rapid succession, parallel npx calls race to refresh the @latest cache
#   and fail with ENOTEMPTY (filesystem atomic-rename collision during
#   ~/.npm/_npx/<hash>/ updates). The failing hook is non-blocking (harness
#   continues) but its capture/redirect is silently skipped, so an unknown
#   percentage of events never reach the context-mode session DB.
#
#   This dispatcher short-circuits to a globally-installed `context-mode`
#   binary when present, entirely bypassing npx for most users (eliminating
#   the race). Falls back to npx only when no global install exists.
#
# Install: copied to .claude/hooks/ by setup.sh --project (phase 51+).
# Register: .claude/settings.json command field:
#   "bash /abs/path/to/.claude/hooks/context-mode-hook-dispatch.sh <event>"
# Events: posttooluse | pretooluse | precompact | sessionstart | userpromptsubmit
#
# Behavior:
#   - Global install present        → exec context-mode hook claude-code <event>
#   - No global install, npx present → exec npx -y context-mode@latest hook claude-code <event>
#   - No global install, no npx      → exit 0 with one-shot stderr notice (fail-open)
#   - No event arg                   → exit 0 (fail-open; hook is non-blocking anyway)
#
#   - pretooluse, Agent/Task prompt already carrying the routing block
#                                    → exit 0, context-mode not called (see guard below)
#
# Input: Claude Code passes the hook payload JSON on stdin. `exec` replaces
# this shell with the target binary, so for every event except pretooluse
# stdin passes through byte-for-byte. pretooluse buffers it for the guard and
# re-feeds it with exactly one trailing newline (harmless to a JSON reader).

set -euo pipefail

event="${1:-}"
if [ -z "$event" ]; then
  echo "context-mode-hook-dispatch: missing event arg" >&2
  exit 0
fi

# Agent re-injection guard. Upstream context-mode (hooks/core/routing.mjs, v1.0.169)
# appends its <context_window_protection> block to every Agent prompt unconditionally.
# When the model re-sends a prompt that a previous pass already rewrote (e.g. retrying
# after agent-cmm-gate blocked it), the prompt gained a SECOND copy, and auto mode could
# no longer classify the launch, so subagent spawns stalled. If the block is already
# present, pass the call through untouched. Only pretooluse pays for buffering stdin;
# every other event still execs straight through. Both the opening AND closing tag must
# be present, so a prompt that merely mentions the tag name still gets routed.
if [ "$event" = "pretooluse" ]; then
  payload="$(cat)"
  if [[ "$payload" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"(Agent|Task)\" ]]; then
    [[ "$payload" == *'<context_window_protection>'*'</context_window_protection>'* ]] && exit 0
    # Auto mode refuses ANY Agent launch whose input a hook rewrote after review
    # ("a hook changed this call's input after auto mode reviewed it") -- 34 of 44
    # such failures over 21 days were FIRST-pass rewrites, so the guard above was
    # not enough. In auto mode skip the rewrite; subagent-ctx-startup.sh still
    # delivers the guidance via SubagentStart, which changes no input.
    [[ "$payload" =~ \"permission_mode\"[[:space:]]*:[[:space:]]*\"auto\" ]] && exit 0
  fi
  exec 0<<<"$payload"
fi

if command -v context-mode >/dev/null 2>&1; then
  exec context-mode hook claude-code "$event"
elif command -v npx >/dev/null 2>&1; then
  exec npx -y context-mode@latest hook claude-code "$event"
else
  # Neither a global `context-mode` binary nor `npx` is available on this host.
  # Rather than letting `exec npx` fail under `set -e` (which emits a noisy
  # "exec: npx: not found" per hook fire), bail out fail-open with a one-shot
  # notice. The hook is non-blocking by contract, so exit 0 lets the user's
  # tool call proceed unaffected; the notice is rate-limited to once per
  # 5-minute window per user so we don't spam the terminal.
  _CMHD_STAMP="/tmp/cmhd-no-runtime-notice-$(id -u)"
  _CMHD_NOW=$(date +%s 2>/dev/null || echo 0)
  _CMHD_LAST=$(date -r "$_CMHD_STAMP" +%s 2>/dev/null || echo 0)
  if [ "$((_CMHD_NOW - _CMHD_LAST))" -ge 300 ]; then
    echo "context-mode-hook-dispatch: neither 'context-mode' nor 'npx' found on PATH; skipping. Install context-mode globally (npm i -g context-mode) to enable capture." >&2
    touch "$_CMHD_STAMP" 2>/dev/null || true
  fi
  exit 0
fi
