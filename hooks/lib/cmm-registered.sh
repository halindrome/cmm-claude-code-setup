#!/bin/bash
# cmm-registered.sh — shared "is codebase-memory-mcp actually registered?" probe.
#
# Install: copied to <base>/hooks/lib/cmm-registered.sh by setup.sh.
# Register: not a hook; sourced by the gate/nudge hooks below.
#
# WHY THIS EXISTS
# ---------------
# Six availability cascades across five hooks each hand-rolled this check, and
# they drifted. Two defects came out of that drift:
#
#   1. They probed exactly ONE global location —
#      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" — while setup.sh
#      probes THREE. A user-scope `claude mcp add` writes to .claude.json, so a
#      perfectly normal install registered CMM somewhere no hook ever looked and
#      every gate silently took its fail-open exit. That is the enforcement this
#      stack exists to provide, absent, with no error.
#
#   2. Grepping for the bare string 'codebase-memory-mcp' anywhere in a settings
#      file is NOT a registration test. A permissions allowlist
#      ("mcp__codebase-memory-mcp__search_graph") contains that string, and so
#      does a rule DENYING those tools. Matching it turns a fail-open bug into a
#      fail-CLOSED one: the user's Grep/Bash get hard-blocked because they
#      mentioned CMM. Fail-closed is strictly worse than fail-open here, because
#      the remedy is a tool call the block itself forbids.
#
# So: probe the same KEY, in the same PLACES, as setup.sh (see its
# _probe_paths list) — mcpServers.codebase-memory-mcp, never a substring.
#
# Usage:
#   source "<lib>/cmm-registered.sh"
#   cmm_is_registered "$REPO_ROOT" && ...   # 0 = registered, 1 = not

# _cmm_config_dir — byte-for-byte mirror of setup.sh's detect_config_dir().
# Duplicated rather than imported because hooks must not source setup.sh. If
# that function changes, change this one: a divergence here silently narrows
# the probe set, which is how a legacy ~/.claude-only install ended up
# unprobed while the installer happily registered CMM there.
_cmm_config_dir() {
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        printf '%s' "$CLAUDE_CONFIG_DIR"
    elif [ -d "$HOME/.config/claude-code" ]; then
        printf '%s' "$HOME/.config/claude-code"
    else
        printf '%s' "$HOME/.claude"
    fi
}

# cmm_is_registered <repo_root>
#   Returns 0 when codebase-memory-mcp is registered as an MCP server in any
#   location Claude Code actually reads, else 1. Never writes, never blocks.
#
# ONE python3 spawn, not one per candidate path. This runs on every Grep and
# Bash tool call via PreToolUse; an interpreter start is ~16ms on a normal dev
# machine, so a path-at-a-time loop cost ~32ms of pure startup per tool call
# for a check that reads at most four small files.
cmm_is_registered() {
    local _root="${1:-}"
    local _cfg
    _cfg="$(_cmm_config_dir)"

    # Exactly the set setup.sh probes: the resolved config dir's settings.json
    # and .claude.json, the user-scope ~/.claude.json that `claude mcp add`
    # writes, and the project .mcp.json.
    CMM_ROOT="$_root" CMM_CFG="$_cfg" python3 -c '
import json, os, sys

root = os.environ.get("CMM_ROOT", "")
cfg = os.environ.get("CMM_CFG", "")
home = os.path.expanduser("~")

paths = []
if root:
    paths.append(os.path.join(root, ".mcp.json"))
if cfg:
    paths.append(os.path.join(cfg, "settings.json"))
    paths.append(os.path.join(cfg, ".claude.json"))
paths.append(os.path.join(home, ".claude.json"))

for p in paths:
    try:
        with open(p) as f:
            d = json.load(f)
    except Exception:
        # Missing, unreadable, a directory, or not JSON — never fatal.
        continue
    if not isinstance(d, dict):
        continue
    servers = d.get("mcpServers")
    if isinstance(servers, dict) and "codebase-memory-mcp" in servers:
        sys.exit(0)
sys.exit(1)
' 2>/dev/null
}

# cmm_project_name -> the CMM project name for the current repo, e.g.
#   /Users/ahby/Sources/my-repo  ->  Users-ahby-Sources-my-repo
#
# WHY THIS EXISTS
# ---------------
# `project` is a REQUIRED argument on search_code, search_graph,
# get_code_snippet, trace_path, query_graph and get_architecture. Every gate in
# this stack used to print a redirect like
#   search_code(query="foo")
# which fails TWICE before it can work: `query` is not a parameter at all (it is
# `pattern`), and `project` is missing. Measured over 30 days of local
# transcripts, the first CMM call after one of our gate blocks failed on
# arguments 8.4% of the time against a 1.3% baseline -- 6.5x. A gate that hands
# back a broken call teaches the agent that CMM does not work, and the observed
# response is to stop using CMM rather than to fix the call.
#
# Mirrors CMM's cbm_project_name_from_path (src/pipeline/fqn.c): canonical
# (symlink-resolved) path; every byte outside [A-Za-z0-9._-] -> "-", except
# non-ASCII bytes, which become two lowercase hex digits; runs of "-" and of "."
# collapsed; leading "-"/"." and trailing "-" trimmed. A plain "/" -> "-" swap
# names a project that does not exist for paths with spaces, "@", "+", etc.
# Prints nothing when the root cannot be determined; callers must omit the
# argument rather than emit an empty one, since project="" fails the same way a
# missing project does.
# ponytail: CMM's filename-length cap (fqn_bound_name_len) is not mirrored —
# only matters for paths longer than a filesystem name component.
cmm_project_name() {
    local root=""
    # Prefer a PROJECT_ROOT already resolved by hooks/lib/project-root.sh.
    if [ -n "${PROJECT_ROOT:-}" ]; then
        root="$PROJECT_ROOT"
    else
        root="$(git rev-parse --show-toplevel 2>/dev/null)"
        # Walk out of submodules so the name matches the monorepo-root index;
        # a subtree index is a DIFFERENT project name and will not resolve.
        if [ -n "$root" ]; then
            local parent
            while parent="$(git -C "$root" rev-parse --show-superproject-working-tree 2>/dev/null)"; do
                [ -n "$parent" ] || break
                root="$parent"
            done
        fi
    fi
    [ -n "$root" ] || return 0
    root="$(cd "$root" 2>/dev/null && pwd -P || printf '%s' "$root")"
    local name
    if [[ "$root" =~ ^[A-Za-z0-9._/-]*$ ]]; then
        name="${root//\//-}"
        while [[ "$name" == *--* ]]; do name="${name//--/-}"; done
        while [[ "$name" == *..* ]]; do name="${name//../.}"; done
    else
        # Bytes outside the safe set: per-byte hex mapping needs python3. Without
        # it, fall back to the separator swap (correct for every safe path).
        name="$(R="$root" python3 -c 'import os, re
out = "".join(chr(b) if (chr(b).isascii() and (chr(b).isalnum() or chr(b) in "._-"))
              else ("%02x" % b if b >= 0x80 else "-")
              for b in os.environ["R"].encode())
out = re.sub(r"-+", "-", re.sub(r"\.+", ".", out))
print(out, end="")' 2>/dev/null)" || name="${root//\//-}"
    fi
    while [[ "$name" == -* || "$name" == .* ]]; do name="${name#?}"; done
    while [[ "$name" == *- ]]; do name="${name%-}"; done
    printf '%s' "${name:-root}"
}

# cmm_checkout_root <path> -> canonical root of the git checkout holding <path>,
# walked out of submodules (CMM indexes the superproject root, so a submodule
# inside it is NOT a separate project). Prints nothing when <path> is not in git.
#
# A linked worktree -- including a worktree of a submodule placed outside its
# superproject -- reports no superproject, so it resolves to its own root: CMM
# indexes it as its own project, named from its own path.
cmm_checkout_root() {
    local p="$1" d top parent
    [ -n "$p" ] || return 0
    if [ -d "$p" ]; then d="$p"; else d="$(dirname "$p")"; fi
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$top" ] || return 0
    while parent="$(git -C "$top" rev-parse --show-superproject-working-tree 2>/dev/null)" && [ -n "$parent" ]; do
        top="$parent"
    done
    (cd "$top" 2>/dev/null && pwd -P) || printf '%s' "$top"
}

# cmm_project_indexed <name> -> 0 when CMM holds an index for project <name>.
# CMM stores one <name>.db per project under $CBM_CACHE_DIR, default
# ~/.cache/codebase-memory-mcp (cbm_resolve_cache_dir, src/foundation/platform.c).
cmm_project_indexed() {
    [ -n "$1" ] && [ -f "${CBM_CACHE_DIR:-$HOME/.cache/codebase-memory-mcp}/$1.db" ]
}

# cmm_other_checkout <target-path> <session-root>
#   -> "<project-name><TAB><checkout-root><TAB><indexed 1|0>" when <target-path>
#      lives in a git checkout OTHER than <session-root> (a linked worktree, a
#      sibling clone); nothing otherwise.
#
# WHY: every gate names project=<session project>. A search aimed at a sibling
# worktree then gets a call against the wrong project -- which comes back empty,
# and an empty result reads as "not indexed". Observed 2026-11-14: a session in
# ../cache-freshness editing ../cache-freshness-wt/rest-api-6932 (a submodule
# worktree outside the superproject) concluded "the worktree isn't in the CMM
# index" and grepped for the rest of the task, never calling index_repository.
cmm_other_checkout() {
    local target="$1" session="$2" top name idx=0
    top="$(cmm_checkout_root "$target")"
    [ -n "$top" ] || return 0
    if [ -n "$session" ]; then
        session="$(cd "$session" 2>/dev/null && pwd -P || printf '%s' "$session")"
        [ "$top" = "$session" ] && return 0
    fi
    name="$(PROJECT_ROOT="$top" cmm_project_name)"
    [ -n "$name" ] || return 0
    cmm_project_indexed "$name" && idx=1
    printf '%s\t%s\t%s' "$name" "$top" "$idx"
}

# cmm_other_checkout_note <name> <root> <indexed> -> the guidance lines a gate
# appends for a target in another checkout. One wording, shared by every gate.
cmm_other_checkout_note() {
    local name="$1" root="$2" idx="$3"
    printf '%s\n' "Note: this target is in a different checkout ($root),"
    printf '%s\n' "which is its own CMM project \"$name\" -- not this session's project."
    if [ "$idx" != 1 ]; then
        printf '%s\n' "It has no CMM index yet. Index it once (allowed: it is not a subtree), then query it:"
        printf '%s\n' "  mcp__codebase-memory-mcp__index_repository(repo_path=\"$root\")"
    fi
    printf '%s' "Pass project=\"$name\" to search_graph / search_code / get_code_snippet there."
}
