#!/bin/bash
# ctx-execute-enforcer.sh — PreToolUse:Bash hook (allowlist enforcer; plugin-form and MCP-server-form coverage)
# BLOCKING: exits 2 for test runners, package installs, linters, and log viewers; redirects to ctx_execute.
# No-op when Context Mode is not installed (neither plugin-form NOR MCP-server-form detected)
# or not yet initialized for this session.
# Phase 57 G3: availability probe checks both install forms — ${CLAUDE_PLUGIN_ROOT} and
# ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/cache/<marketplace>/context-mode/.claude-plugin/plugin.json (plugin form)
# as a fast-path before falling through to the legacy .mcp.json probe.
#
# Install: cp hooks/project/ctx-execute-enforcer.sh .claude/hooks/ && chmod +x .claude/hooks/ctx-execute-enforcer.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/ctx-execute-enforcer.sh"}] }] }
# Matcher: PreToolUse:Bash
# 47-02: git log/diff/show bare forms and echo/printf removed from exempt list.

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
fi

# --- Path Integrity Check ---
# Hooks are registered with absolute paths by setup.sh. If the project was moved or
# cloned without re-running setup.sh, BASH_SOURCE points to the old location while
# git resolves the actual current root — catch this mismatch early.
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'."
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force"
    exit 2
fi

# --- Input Parsing ---
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# If parsing failed or command is empty, do not block — fail open to avoid spurious hook errors
[ -z "$COMMAND" ] && exit 0

# --- Context Mode Detection (shared library) ---
# The probe verifies context-mode is LOADABLE, not merely present on disk:
# a plugin whose registered installPath does not resolve here (the devcontainer
# bind-mount case) registers no ctx_* tools, and this hook must not mandate a
# tool that does not exist. See hooks/lib/context-mode-detect.sh.
_CM_LIB=""
for _d in "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    [ -f "$_d/context-mode-detect.sh" ] && { _CM_LIB="$_d/context-mode-detect.sh"; break; }
done
if [ -n "$_CM_LIB" ]; then
    source "$_CM_LIB"
    detect_context_mode "$PROJECT_ROOT" "/tmp/ctx-enforcer-${PROJECT_HASH}"
else
    # Partial install (lib missing) — fail open rather than enforce blindly.
    # Re-run: bash setup.sh --project --force
    exit 0
fi

# No-op if Context Mode is not installed
if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
    exit 0
fi

# --- Context Mode Liveness Check (deadlock prevention + dead-server fail-open) ---
# The sentinel carries a VERDICT, not merely existence. Two writers, two meanings:
#
#   "ready" — cmm-session-start.sh, from detect_context_mode's on-disk check.
#             OPTIMISTIC. Presence on disk is NOT proof the MCP registered: while
#             Claude Code re-extracts the plugin cache, installPath exists but the
#             server never starts. Enforcing on "ready" is what wedged a session
#             for 24 minutes — every Bash call blocked, redirected to ctx_* tools
#             that were never registered, with no escape hatch.
#
#   "live"  — context-mode-sentinel-writer.sh, PostToolUse on a real ctx_* call.
#             The server answered, so the tools provably exist.
#
# Enforce only on "live", and only while it is fresh. Every ctx_* call rewrites
# the file, so a server that dies mid-session goes stale and enforcement lifts
# within the TTL instead of wedging the session until restart.
#
# Trade-off, stated plainly: enforcement does not arm until the first successful
# ctx_* call of a session. That is the point — a hook must not mandate a tool it
# has never seen work. Same rule as hooks/lib/context-mode-detect.sh.
CONTEXT_MODE_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"
CONTEXT_MODE_TTL_MIN="${CTX_ENFORCER_TTL_MIN:-30}"
[ -f "$CONTEXT_MODE_SENTINEL" ] || exit 0
grep -q '^live$' "$CONTEXT_MODE_SENTINEL" 2>/dev/null || exit 0
[ -n "$(find "$CONTEXT_MODE_SENTINEL" -mmin "-${CONTEXT_MODE_TTL_MIN}" 2>/dev/null)" ] || exit 0

# --- Bypass Marker ---
# Internal bypass marker — undocumented, for operator use only.
if echo "$COMMAND" | grep -q "ctx-exempt"; then
    exit 0
fi

# --- Compound-shell normalization (Phase 61 follow-up) ---
# Agents frequently bypass exemptions by prefixing with `cd <dir> && <command>`
# because `cd ` matches the navigation exemption. Peel off any leading
# `cd <single-token> &&` prefixes so the EFFECTIVE command is what gets
# matched against exemption patterns below. Anything still compound after
# peeling falls through to the default block — exemption patterns assume a
# single bounded command.
_ORIG_COMMAND="$COMMAND"
while [[ "$COMMAND" =~ ^[[:space:]]*cd[[:space:]]+\"[^\"]*\"[[:space:]]*\&\&[[:space:]]* ]] || \
      [[ "$COMMAND" =~ ^[[:space:]]*cd[[:space:]]+\'[^\']*\'[[:space:]]*\&\&[[:space:]]* ]] || \
      [[ "$COMMAND" =~ ^[[:space:]]*cd[[:space:]]+[^[:space:]\&\|\;]+[[:space:]]*\&\&[[:space:]]* ]]; do
    COMMAND="${COMMAND#${BASH_REMATCH[0]}}"
done
# If the stripped command still has compound shell operators, do NOT exempt —
# fall straight through to the default block path. Detected operators:
# `&&`, `||`, unquoted `;`, unquoted `|`, `$(...)`, backtick command subs,
# bare `&` (backgrounding), and embedded newlines (multi-command payloads —
# an unquoted newline is a command separator that otherwise rides the `cd *`
# navigation exemption).
#
# Quote-awareness: strip single-quoted and double-quoted substrings before the
# operator scan so legitimate exempt commands carrying these characters inside
# string arguments (e.g. `git commit -m "wip; cleanup"`, `sed 's/a|b/x/'`) are
# not false-positive blocked. Quoted spans may cross newlines (e.g. a multi-line
# `git commit -m "..."`), so the scrub is whole-string, not line-based: a
# line-based sed leaves the embedded newline in place and false-positives the
# newline check above. No attempt to handle escape sequences or here-docs.
# Falls back to the raw command (safe — may over-block) if python3 is absent.
_OPCHECK=$(COMMAND="$COMMAND" python3 <<'PY' 2>/dev/null
import os, re, sys
c = os.environ.get("COMMAND", "")
c = re.sub(r"'[^']*'", "", c, flags=re.S)
c = re.sub(r'"[^"]*"', "", c, flags=re.S)
sys.stdout.write(c)
PY
) || _OPCHECK="$COMMAND"
if [[ "$_OPCHECK" == *"&&"* ]] || [[ "$_OPCHECK" == *"||"* ]] || \
   [[ "$_OPCHECK" == *";"* ]]   || [[ "$_OPCHECK" == *"|"* ]]  || \
   [[ "$_OPCHECK" == *'$('* ]]  || [[ "$_OPCHECK" == *'`'* ]]  || \
   [[ "$_OPCHECK" == *"&"* ]]   || [[ "$_OPCHECK" == *$'\n'* ]]; then
    bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "bash-compound" 2>/dev/null || true
    # A bare code="..." placeholder is where the laundering happens: the agent
    # refills it with the original command, truncating pipe and all. Measured
    # 2026-09-03: of 1,501 blocked Bash calls that escalated into a ctx_* call,
    # 252 carried the identical `| head -N` into the sandbox, where nothing
    # inspected it. When the command carries a truncation, name the stripped
    # replacement concretely instead of leaving a blank to fill in.
    _SUGGEST=$(printf '%s' "$_ORIG_COMMAND" | sed -E 's/[[:space:]]*\|[[:space:]]*(head|tail)[^|;&]*//g')
    if [ "$_SUGGEST" != "$_ORIG_COMMAND" ]; then
        _OPT2="       mcp__plugin_context-mode_context-mode__ctx_execute(language=\"shell\", code=\"$_SUGGEST\", intent=\"<what you are looking for>\")
     The truncating pipe is dropped on purpose: ctx_execute indexes the FULL
     output and returns only the sections matching intent=, so capping it first
     discards data for no context saving. Re-adding it will be blocked by
     ctx-payload-guard."
    else
        _OPT2="       mcp__plugin_context-mode_context-mode__ctx_execute(language=\"shell\", code=\"$_ORIG_COMMAND\", intent=\"<what you are looking for>\")"
    fi
    cat >&2 <<COMPOUND
BLOCKED: Compound shell command cannot be exempted.

Detected:
  $_ORIG_COMMAND

Exemption patterns (cd, git status, ls, mkdir, …) only apply to single bounded
commands. Compounds like \`cd <dir> && <cmd>\` or \`<cmd> | <cmd>\` can hide
arbitrary output behind an exempt prefix.

Fix options:
  1. Use absolute paths and drop the \`cd\` prefix.
  2. Route the real command through ctx_execute for output sandboxing:
$_OPT2
  3. Run the two halves as separate Bash calls if both are independently exempt.
COMPOUND
    exit 2
fi

# --- Exempt Patterns (always allow, exit 0) ---
# Each exempt group increments a bash-exempt counter via track-hook-blocks.sh
# for audit instrumentation (47-02). Non-blocking; exit-0 outcome unchanged.
_track_exempt() {
  bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "bash-exempt" "$1" 2>/dev/null || true
}

# --- Git global-flag normalization ---
# The git exemptions below anchor on `git ` followed immediately by the
# subcommand, so any global flag in between defeats every one of them. That
# silently contradicts cwd-guard.sh, which tells the agent to prefer
# `git -C apps/rest-api status` over `cd apps/rest-api && git status` — and in
# a submodule/monorepo checkout it left NO unblocked path to commit, since the
# `cd … &&` alternative is rejected by the compound check above.
#
# Peel leading repo-selection flags into _EXEMPT_CMD so the exemption patterns
# match on the effective subcommand. Only _EXEMPT_CMD is normalized; $COMMAND
# stays intact for the block messages below.
#
# Deliberately narrow: only flags that select WHICH repo/config git acts on.
# Anything else (notably `-c alias.x=!cmd`) is left in place, so it fails to
# match any exemption and falls through to the default block.
#
# Known limitation: word-splitting is quote-blind, so `-C "my dir"` peels only
# the first token and the leftover fails to match — blocked, not wrongly
# exempted. Fail-closed is the correct direction here.
_EXEMPT_CMD="$COMMAND"
if [[ "$_EXEMPT_CMD" =~ ^[[:space:]]*git([[:space:]]|$) ]]; then
  read -ra _GTOK <<< "$_EXEMPT_CMD"
  _gi=1
  while [ "$_gi" -lt "${#_GTOK[@]}" ]; do
    case "${_GTOK[$_gi]}" in
      # flag + separate value → skip two tokens
      -C|--git-dir|--work-tree|--namespace)          _gi=$((_gi + 2)) ;;
      # self-contained flag → skip one token
      --git-dir=*|--work-tree=*|--namespace=*)       _gi=$((_gi + 1)) ;;
      --no-pager|--no-replace-objects|--bare)        _gi=$((_gi + 1)) ;;
      *) break ;;
    esac
  done
  if [ "$_gi" -gt 1 ] && [ "$_gi" -lt "${#_GTOK[@]}" ]; then
    _EXEMPT_CMD="git ${_GTOK[*]:$_gi}"
  fi
fi

# Git write operations (state-changing, bounded output, required for workflow)
case "$_EXEMPT_CMD" in
  git\ commit*|git\ add*|git\ push*|git\ pull*|git\ fetch*)  _track_exempt git-write; exit 0 ;;
  git\ checkout*|git\ switch*|git\ branch*|git\ tag*)         _track_exempt git-write; exit 0 ;;
  git\ rebase*|git\ merge*|git\ cherry-pick*|git\ reset*)     _track_exempt git-write; exit 0 ;;
  git\ stash*|git\ worktree*|git\ remote*)                    _track_exempt git-write; exit 0 ;;
  git\ config*|git\ init*)                                    _track_exempt git-write; exit 0 ;;
esac

# Git bounded read operations (output is short and predictable)
case "$_EXEMPT_CMD" in
  git\ status|git\ status\ *)                                                _track_exempt git-bounded-read; exit 0 ;;
  git\ diff\ --stat*|git\ log\ --oneline\ -*)                                _track_exempt git-bounded-read; exit 0 ;;
  git\ log\ --name-only*|git\ log\ --stat*|git\ show\ --name-only*)          _track_exempt git-bounded-read; exit 0 ;;
  git\ show\ --stat*|git\ rev-parse\ *|git\ rev-list\ --count*)              _track_exempt git-bounded-read; exit 0 ;;
esac

# Filesystem mutations (no stdout flood)
case "$COMMAND" in
  mkdir\ *|rmdir\ *|rm\ *|mv\ *|cp\ *|ln\ *|chmod\ *|chown\ *)  _track_exempt filesystem; exit 0 ;;
  touch\ *|install\ -m*|mktemp*)                                 _track_exempt filesystem; exit 0 ;;
esac

# Navigation and short queries (output is bounded)
case "$COMMAND" in
  cd\ *|pwd|which\ *|type\ *|command\ -v\ *)     _track_exempt navigation; exit 0 ;;
  date*|uname*|whoami|hostname)                  _track_exempt navigation; exit 0 ;;
esac

# Short-read utilities (bounded output)
case "$COMMAND" in
  wc\ *|head\ *|tail\ -[0-9]*|tail\ -n\ [0-9]*)  _track_exempt short-reads; exit 0 ;;
  ls|ls\ *)                                       _track_exempt short-reads; exit 0 ;;
esac

# Shell syntax checks (parse-only: no stdout on success, short error output on failure).
# Routing these through ctx_execute is pure friction — there is nothing to sandbox.
case "$COMMAND" in
  bash\ -n\ *|sh\ -n\ *|zsh\ -n\ *|dash\ -n\ *)  _track_exempt syntax-check; exit 0 ;;
  bash\ -n|sh\ -n|zsh\ -n|dash\ -n)              _track_exempt syntax-check; exit 0 ;;
esac

# Remote commands (output belongs to remote context, not local CTX store)
case "$COMMAND" in
  ssh\ *|scp\ *|rsync\ *|sftp\ *)                _track_exempt remote; exit 0 ;;
esac

# VBW/planning scripts (must not break planning workflows)
case "$COMMAND" in
  */.vbw-planning/*|*/tmp/.vbw-plugin-root-link-*)                            _track_exempt vbw-planning; exit 0 ;;
  bash\ */.vbw-planning/*|bash\ */tmp/.vbw-plugin-root-link-*)                _track_exempt vbw-planning; exit 0 ;;
esac

# Package/tool version queries (bounded output) — narrowly scoped.
# The long form --version is unambiguous, so exempt it anywhere it appears.
case "$COMMAND" in
  *--version)   _track_exempt version; exit 0 ;;
esac
# The short forms -v / -V are OVERLOADED with "verbose": a blanket `* -v` match
# wrongly exempts verbose test runs (e.g. `pytest -v`, `pytest tests/ -v`) and
# leaks the full log to context as plain Bash. Exempt only a BARE version query —
# exactly two tokens `<tool> -v|-V` — and never when the tool is a known
# test/build/lint runner (whose -v means verbose). A real version check carries
# no other arguments; a test run does.
case "$COMMAND" in
  *\ -v|*\ -V)
    read -ra _VTOK <<< "$COMMAND"
    if [ "${#_VTOK[@]}" -eq 2 ]; then
      case "${_VTOK[0]}" in
        pytest|py.test|prove|jest|mocha|vitest|jasmine|ava|tap|phpunit|pest|rspec|minitest|tox|nose2|nosetests|behave|cucumber|bats|go|cargo|make|gmake|npm|npx|yarn|pnpm|gradle|gradlew|mvn|ctest|rake|playwright|cypress|dotnet|ninja)
          : ;;  # verbose flag on a runner — fall through to the default block
        *)
          _track_exempt version; exit 0 ;;
      esac
    fi
    ;;
esac

# --- Default: block everything not explicitly exempt ---
# Allowlist model: only commands matching exempt patterns above pass through.
# Everything else must go through ctx_execute for output sandboxing.
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "bash" 2>/dev/null || true

# NOTE: no truncation-stripping here. An unquoted `| head` always trips the
# compound-command check above and is handled there, where the strip is tested.
# The only way to reach this branch with `| head` in the text is inside quotes
# (`echo "x | head"`), where stripping would mangle a correct command.
cat >&2 <<BLOCKED
BLOCKED: Route this command through ctx_execute for output sandboxing.

Replace:
  Bash("$COMMAND")
With (plugin form):
  mcp__plugin_context-mode_context-mode__ctx_execute(language="shell", code="$COMMAND", intent="<what you are looking for>")
Or (MCP-server form, legacy):
  mcp__context-mode__ctx_execute(language="shell", code="$COMMAND", intent="<what you are looking for>")

Context Mode captures only the relevant output portion, preventing context bloat.
If this is a source-code search, prefer search_code / search_graph (CMM) over ctx_execute.
See skill \`ctx-rules\` for the full protocol.
BLOCKED
exit 2
