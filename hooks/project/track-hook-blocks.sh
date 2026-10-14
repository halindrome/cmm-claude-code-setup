#!/bin/bash
# track-hook-blocks.sh — Inline call from blocking hooks to increment block counts
# Usage: bash .claude/hooks/track-hook-blocks.sh <type> [reason]
#   types: read | bash | ctx_payload | bash_exempt | bash_unarmed
# Silent, never blocks, always exits 0.
#
# Install: cp hooks/project/track-hook-blocks.sh .claude/hooks/ && chmod +x .claude/hooks/track-hook-blocks.sh
# Called by: cmm-nudge.sh (read blocks), ctx-execute-enforcer.sh (bash blocks,
#            exemptions, and unarmed passes)
#
# NOT-A-BLOCK TYPES
# -----------------
# `bash_exempt` and `bash_unarmed` record a command the enforcer ALLOWED. They
# must not bump total_blocks -- an allow is not a block, and counting it as one
# inflates the very number used to judge whether the gate is working. Every
# unrecognised type used to land in exactly that hole: it fell through all the
# branches below, incremented total_blocks, and recorded nothing in by_hook, so
# the miscount was invisible. Unknown types are now explicitly not counted.

HOOK_TYPE="${1:-unknown}"
# Optional second argument: why. Only meaningful for the not-a-block types.
HOOK_REASON="${2:-}"

# --- Project Root Detection (same pattern as track-cmm-calls.sh) ---
# Walk the git superproject chain to find the outermost project root.
# Handles arbitrarily nested submodules. Falls back to BASH_SOURCE traversal.
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
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"

# --- Git Worktree Detection ---
# git worktrees share the main repo but show-superproject-working-tree returns empty.
# Detect via git-common-dir: in a worktree it points to the main .git dir.
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

# Legacy orphaned .git/modules/<name>/ recovery — matches hooks/lib/project-root.sh
if [ -n "$PROJECT_ROOT" ]; then
    case "$PROJECT_ROOT" in
      */.git/*)
        _MODULES_OWNER="${PROJECT_ROOT%%/.git/*}"
        if [ -n "$_MODULES_OWNER" ] && [ -d "$_MODULES_OWNER" ]; then
            _CANDIDATE="$(cd "$_MODULES_OWNER" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
            case "$_CANDIDATE" in
              */.git/*|"") : ;;
              *) PROJECT_ROOT="$_CANDIDATE" ;;
            esac
        fi
        ;;
    esac
fi

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')

COUNTER_DIR="$HOME/.cache/codebase-memory-mcp"
COUNTER_FILE="${COUNTER_DIR}/_block-counts-${PROJECT_HASH}.json"
mkdir -p "$COUNTER_DIR" 2>/dev/null

TEMP=$(mktemp)
HOOK_TYPE="$HOOK_TYPE" HOOK_REASON="$HOOK_REASON" COUNTER_FILE="$COUNTER_FILE" TEMP="$TEMP" python3 -c "
import json, os, re

hook_type = os.environ['HOOK_TYPE']
hook_reason = os.environ.get('HOOK_REASON', '')
counter_file = os.environ['COUNTER_FILE']
temp_path = os.environ['TEMP']

# Read existing data or start fresh
try:
    with open(counter_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {'total_blocks': 0, 'read_blocks': 0, 'bash_blocks': 0, 'by_hook': {}}

# Callers spell the type with either separator ('bash-compound', 'bash_unarmed').
hook_type = hook_type.replace('-', '_')

ALLOW_TYPES = ('bash_exempt', 'bash_unarmed')

# Every type any hook in this stack passes, mapped to its by_hook key. Keep this
# table in sync with the call sites -- grep hooks/ for track-hook-blocks.sh
# invocations. NOTE: this whole program is passed to python3 -c inside a
# DOUBLE-QUOTED shell string, so a literal double quote anywhere in it (even in
# a comment) closes that string early and silently truncates the program: it
# then writes nothing, exits 0, and the caller moves an empty temp file over the
# counter. Use single quotes only, here and below.
# It is a TABLE and not an if/elif chain because the chain was the bug: types
# with no branch (bash_nav, grep, ctx_execute, webfetch) bumped total_blocks and
# recorded nothing, so total_blocks and by_hook disagreed and the CMM gates --
# the two whose conversion rate we actually care about -- were invisible.
# 'grep' is sent by BOTH cmm-grep-nudge.sh and grep-cmm-gate.sh; they cannot be
# told apart from the argument alone, so they share one key.
BLOCK_KEYS = {
    'read':          ('read_blocks',        'cmm-nudge'),
    'bash':          ('bash_blocks',        'ctx-execute-enforcer'),
    'bash_compound': ('bash_blocks',        'ctx-execute-enforcer'),
    'bash_nav':      ('bash_blocks',        'cmm-grep-nudge'),
    'grep':          ('grep_blocks',        'grep-cmm-gate'),
    'ctx_execute':   ('ctx_execute_blocks', 'ctx-execute-cmm-nudge'),
    'ctx_payload':   ('ctx_payload_blocks', 'ctx-payload-guard'),
    'webfetch':      ('webfetch_blocks',    'webfetch-nudge'),
}

# Types that record an ALLOW, not a block. Handled before the total_blocks bump
# so they can never inflate it. Genuinely unknown types land here too: recording
# nothing is correct, silently counting them as a block is not.
if hook_type in ALLOW_TYPES or hook_type not in BLOCK_KEYS:
    if hook_type in ALLOW_TYPES:
        # Reason is hook-supplied, but sanitise before it becomes a JSON key.
        reason = re.sub(r'[^a-z0-9-]', '', (hook_reason or 'unspecified').lower())[:32] or 'unspecified'
        key = 'ctx-execute-enforcer-%s-%s' % (hook_type.split('_')[1], reason)
        data.setdefault('allows', {})[key] = data.get('allows', {}).get(key, 0) + 1
    with open(temp_path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    raise SystemExit(0)

# Increment counters
data['total_blocks'] = data.get('total_blocks', 0) + 1
bucket, hook_key = BLOCK_KEYS[hook_type]
data[bucket] = data.get(bucket, 0) + 1
data.setdefault('by_hook', {})[hook_key] = data.get('by_hook', {}).get(hook_key, 0) + 1

# Write to temp file
with open(temp_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null && mv "$TEMP" "$COUNTER_FILE" 2>/dev/null || rm -f "$TEMP"

exit 0
