#!/bin/bash
# ctx-execute-cmm-nudge.sh — PreToolUse hook: hard-block source-code search laundered through ctx_execute in indexed CMM repos (plugin-form and MCP-server-form coverage).
# BLOCKING: exits 2 when tool_input.code is an unambiguous grep/rg/ack/ag/ugrep/find-name against an indexed project path.
# WARNING: a recursive search inside a compound or multi-line payload (cd X && grep -rn ...) exits 0 with an additionalContext advisory; anything else exits 0 silently.
#
# Install: cp hooks/project/ctx-execute-cmm-nudge.sh .claude/hooks/ && chmod +x .claude/hooks/ctx-execute-cmm-nudge.sh
# Register in .claude/settings.json (Phase 57 G3 — plugin-form FIRST, MCP-server-form second):
#   "hooks": { "PreToolUse": [{
#     "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute|mcp__context-mode__ctx_execute",
#     "hooks": [{"type": "command", "command": "bash .claude/hooks/ctx-execute-cmm-nudge.sh"}] }] }
# Matcher: PreToolUse: plugin-form (mcp__plugin_context-mode_context-mode__ctx_execute) OR
#                      MCP-server-form (mcp__context-mode__ctx_execute) — see internal tool_name probe.
#
# Sibling of hooks/project/grep-cmm-gate.sh (Grep-tool hard block). Same REPLACE WITH: machine-readable recovery format.
# Parser is intentionally conservative per 46-CONTEXT.md — single-statement, pipe-less, heredoc-less command lines only; anything else fails open.

# --- Input Parsing ---
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Parse JSON + classify the code field in one python3 block.
# Output (one per line):
#   1: tool_name
#   2: kind (grep-family | find-name | other | exempt | empty)
#   3: pattern (extracted search term; empty when kind=other/exempt/empty)
#   4: target_path (extracted last positional arg, or empty)
#   5: cwd
PARSED=$(echo "$INPUT" | python3 -c "
import sys, json, re, shlex, os

def emit(tool_name='', kind='other', pattern='', target='', cwd=''):
    print(tool_name)
    print(kind)
    print(pattern)
    print(target)
    print(cwd)

try:
    d = json.load(sys.stdin)
except Exception:
    emit()
    sys.exit(0)

tool_name = d.get('tool_name','') or ''
ti = d.get('tool_input',{}) or {}
cwd = d.get('cwd','') or ''

# ctx_execute / ctx_execute_file carry the payload in .code; ctx_batch_execute
# carries a list of {label, command}. Registering only ctx_execute left the
# batch tool completely ungated: a blocked Bash grep became
# ctx_batch_execute(grep -rn ...) and sailed through. Reported by a live session
# 2026-09-04: the two hooks composed into a hole rather than a fence.
# NOTE: this whole program is passed to python3 -c inside a DOUBLE-QUOTED shell
# string, so a literal double quote anywhere in it -- even in a comment --
# truncates the program silently; it then prints nothing and the caller fails
# open. Single quotes only, here and below.
_cmds = []
if tool_name.endswith('ctx_batch_execute'):
    for _c in (ti.get('commands') or []):
        if isinstance(_c, dict) and isinstance(_c.get('command'), str):
            _cmds.append(_c['command'])
else:
    _cmds.append(ti.get('code','') or '')

# Classify on the first command that LOOKS like a code search, so one grep
# hidden among several batch commands is still caught. This verb set mirrors
# GREP_FAMILY below and must stay in lockstep with it.
_SEARCH_VERBS = ('grep', 'egrep', 'fgrep', 'rg', 'ack', 'ag', 'ugrep', 'find')
code = _cmds[0] if _cmds else ''
for _c in _cmds:
    _toks = _c.strip().split()
    if _toks and _toks[0].rsplit('/', 1)[-1] in _SEARCH_VERBS:
        code = _c
        break

# Accept both install-form prefixes across all THREE ctx execution tools. The
# install matcher in setup.sh, this set, and the 'case \$TOOL_NAME' block near
# the bottom of this file are three layers that must agree — the header note
# warned that widening the matcher requires updating all of them together, and
# that is what this change does. Previously only ctx_execute was routed, which
# made ctx_batch_execute a documented-in-hindsight bypass.
# Any other tool_name routes to 'other' and exits 0 (no nudge needed).
_ACCEPTED = {
    'mcp__plugin_context-mode_context-mode__ctx_execute',
    'mcp__plugin_context-mode_context-mode__ctx_execute_file',
    'mcp__plugin_context-mode_context-mode__ctx_batch_execute',
    'mcp__context-mode__ctx_execute',
    'mcp__context-mode__ctx_execute_file',
    'mcp__context-mode__ctx_batch_execute',
}
if tool_name not in _ACCEPTED:
    emit(tool_name, 'other', '', '', cwd)
    sys.exit(0)

if not code.strip():
    emit(tool_name, 'empty', '', '', cwd)
    sys.exit(0)

# Exempt marker anywhere in code
if '# cmm-exempt' in code:
    emit(tool_name, 'exempt', '', '', cwd)
    sys.exit(0)

# Conservative parser: reject any ambiguity -> kind 'other' (fail open)
# Reject: pipes, semicolons, &&, ||, heredocs, backticks, \$(...), multi-line, leading keyword
# Metacharacters INSIDE quotes do NOT count as shell operators.
def _strip_quoted(s):
    # Remove single/double-quoted substrings so subsequent metachar checks only see
    # unquoted shell text. Conservative: on mismatched quotes, return original (parser
    # will likely fail downstream anyway -> fail open).
    out = []
    i = 0; n = len(s)
    while i < n:
        c = s[i]
        if c == '\\\\' and i + 1 < n:
            i += 2
            continue
        if c == \"'\":
            j = s.find(\"'\", i + 1)
            if j == -1:
                return s
            i = j + 1
            continue
        if c == '\"':
            j = i + 1
            while j < n:
                if s[j] == '\\\\' and j + 1 < n:
                    j += 2
                    continue
                if s[j] == '\"':
                    break
                j += 1
            if j >= n:
                return s
            i = j + 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)

def is_simple_single_statement(s):
    stripped = s.strip()
    if not stripped:
        return False
    # Multi-line command text (more than one non-blank non-comment line)
    non_blank_lines = [l for l in stripped.splitlines() if l.strip() and not l.strip().startswith('#')]
    if len(non_blank_lines) != 1:
        return False
    line = non_blank_lines[0]
    # Check metacharacters only OUTSIDE quotes
    unquoted = _strip_quoted(line)
    forbidden = ['|', ';', '&&', '||', '<<', '\`', '\$(']
    for tok in forbidden:
        if tok in unquoted:
            return False
    # Leading shell keywords that begin compound commands
    first_word = line.split(None, 1)[0] if line.split() else ''
    if first_word in ('for','while','if','case','until','select','function','{','('):
        return False
    return True

GREP_FAMILY = {'grep','egrep','fgrep','rg','ripgrep','ack','ag','ugrep'}

def extract_grep_family(toks, tool_first):
    # First non-flag positional arg is the pattern; last remaining positional is target path.
    positionals = []
    i = 1
    skip_next = False
    # Value-taking flags, conservative. -r takes a value only in rg (--replace); it is boolean
    # in grep/egrep/fgrep/ack/ag/ugrep. -o is boolean everywhere we care about. Treating either
    # as value-taking consumed the next token and either masked the pattern or shifted it to
    # the target (QA round 1 M1).
    value_flags = {'-e','--regexp','-f','--file','--include','--exclude','--exclude-dir','-m','--max-count','-A','--after-context','-B','--before-context','-C','--context','-g','--glob','-t','--type','--type-add','--replace'}
    if tool_first in ('rg','ripgrep'):
        value_flags = value_flags | {'-r'}
    explicit_pattern = None
    while i < len(toks):
        t = toks[i]
        if skip_next:
            skip_next = False
            i += 1
            continue
        if t == '--':
            # rest are positional
            positionals.extend(toks[i+1:])
            break
        if t.startswith('-'):
            # -e PATTERN: treat next token as explicit pattern
            if t in ('-e','--regexp','-f','--file') and i+1 < len(toks):
                if t in ('-e','--regexp') and explicit_pattern is None:
                    explicit_pattern = toks[i+1]
                skip_next = True
                i += 1
                continue
            # --include=... attached-value form: ignore
            if '=' in t:
                i += 1
                continue
            # Other value-taking flags we recognize
            if t in value_flags and i+1 < len(toks):
                skip_next = True
                i += 1
                continue
            # Bare boolean flag
            i += 1
            continue
        positionals.append(t)
        i += 1
    if explicit_pattern is not None:
        pattern = explicit_pattern
        target = positionals[-1] if positionals else ''
    else:
        if not positionals:
            return ('', '')
        pattern = positionals[0]
        target = positionals[-1] if len(positionals) > 1 else ''
    return (pattern, target)

def extract_find_name(toks):
    # Look for '-name GLOB'. Target is the first positional directory before any flag.
    # Only classify as find-name if the glob ends in a code extension.
    CODE_EXTS = {'.go','.py','.js','.jsx','.ts','.tsx','.sh','.bash','.rs','.java','.rb','.c','.cc','.cpp','.cxx','.h','.hpp','.swift','.kt','.php','.cs','.scala','.lua','.zig','.ex','.exs','.hs','.dart','.pl','.pm','.groovy','.erl','.r','.clj','.fs','.jl','.el','.cu','.sql','.vue','.svelte','.graphql','.proto','.ml','.m','.mm','.nix','.elm','.lean','.f90','.f95','.f03','.f08','.cuh','.v','.sv','.glsl','.frag','.vert'}
    target = ''
    glob_val = None
    i = 1
    # target = first positional arg (before any -flag)
    while i < len(toks):
        t = toks[i]
        if t.startswith('-') or t in ('(',')','!'):
            break
        target = t
        i += 1
    # Scan for -name
    j = 1
    while j < len(toks) - 1:
        if toks[j] in ('-name','-iname'):
            glob_val = toks[j+1]
            break
        j += 1
    if glob_val is None:
        return (None, '', '')
    # Strip wildcards from glob for pattern extraction
    stripped = glob_val.lstrip('*').rstrip('*')
    # Determine extension
    ext = ''
    if '.' in glob_val:
        ext = '.' + glob_val.rsplit('.', 1)[-1].rstrip('*')
    if ext and ext.lower() in CODE_EXTS:
        # Use the bare stem (without *) as the pattern if non-empty; else the extension stem
        pat = stripped.rstrip('.') or ext.lstrip('.')
        return ('find-name', pat, target)
    # Not a code extension -> not a code-search
    return (None, '', '')

# Compound payloads (cd X && grep -rn ..., multi-line scripts, a search buried in
# a batch) are WARNED, not blocked: such scripts legitimately grep unindexed
# files (binaries, extensionless Dockerfile-* variants, excluded dirs). A 30-day
# transcript replay (2026-10-23) found the single-statement parser above saw
# ~1.4% of source searches in indexed repos -- 33 of ~2,330; the rest were
# cd-prefixed or multi-line. Only a RECURSIVE search at a command position
# counts: a grep after a pipe is a filter, and a grep on one file is not a
# codebase search.
_RECURSIVE_BY_DEFAULT = {'rg', 'ripgrep', 'ag', 'ack', 'ugrep'}
_OPS = set('();<>|&')
_SEG_SKIP = {'do', 'then', 'else', '{', '!', 'time', 'command', 'exec'}

def _segments(line):
    # Yield (tokens, operator-before-them) for each simple command in a line.
    lx = shlex.shlex(line, posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    seg, prev = [], ''
    for t in lx:
        if t and all(ch in _OPS for ch in t):
            if seg and seg[-1].isdigit() and ('>' in t or '<' in t):
                seg.pop()   # the 2 of 2>/dev/null is not a positional
            yield seg, prev
            seg, prev = [], t
        else:
            seg.append(t)
    yield seg, prev

def _compound_search(cmds):
    # Return (pattern, absolute target) for the first recursive search, else None.
    for c in cmds:
        if '# cmm-exempt' in c:
            continue
        cd = ''
        for ln in c.replace('\\\\\n', ' ').splitlines():
            try:
                segs = list(_segments(ln))
            except Exception:
                continue
            for seg, prev in segs:
                if '|' in prev or '<' in prev or '>' in prev:
                    continue
                while seg and seg[0] in _SEG_SKIP:
                    seg = seg[1:]
                if not seg:
                    continue
                verb = seg[0].rsplit('/', 1)[-1]
                if verb == 'cd' and len(seg) > 1:
                    cd = os.path.join(cd, os.path.expanduser(seg[1]))
                    continue
                rec = verb in _RECURSIVE_BY_DEFAULT
                if verb == 'git' and 'grep' in seg:
                    seg = seg[seg.index('grep'):]
                    verb, rec = 'grep', True
                if verb in GREP_FAMILY:
                    rec = rec or any(t == '--recursive' or (t.startswith('-') and not t.startswith('--') and ('r' in t or 'R' in t)) for t in seg[1:])
                    if not rec:
                        continue
                    pat, tgt = extract_grep_family(seg, verb)
                elif verb == 'find':
                    kind, pat, tgt = extract_find_name(seg)
                    if kind is None:
                        continue
                else:
                    continue
                if pat:
                    return pat, os.path.normpath(os.path.join(cwd, cd, tgt or '.'))
    return None

def _other():
    r = _compound_search(_cmds)
    if r:
        emit(tool_name, 'compound-search', r[0], r[1], cwd)
    else:
        emit(tool_name, 'other', '', '', cwd)
    sys.exit(0)

if not is_simple_single_statement(code):
    _other()

line = [l for l in code.strip().splitlines() if l.strip() and not l.strip().startswith('#')][0]

# Tokenize respecting quotes
try:
    tokens = shlex.split(line, posix=True)
except Exception:
    _other()

if not tokens:
    _other()

first = tokens[0]
# Sub-command laundering: git <git-opts...> grep ... is still a grep invocation.
# Skip leading git-level options (-c key=val, -C path, --git-dir=..., --work-tree=...,
# --no-pager, -p/--paginate, --bare, --no-replace-objects, --exec-path[=...], --namespace[=...])
# and unwrap to the subcommand. If the subcommand is grep, treat the remainder as a grep call.
if first == 'git' and len(tokens) >= 2:
    git_value_opts = {'-c','-C','--git-dir','--work-tree','--namespace','--exec-path','--super-prefix','--list-cmds','--attr-source'}
    j = 1
    while j < len(tokens):
        t = tokens[j]
        if not t.startswith('-'):
            break
        # attached-value form: --flag=value
        if '=' in t:
            j += 1
            continue
        if t in git_value_opts and j + 1 < len(tokens):
            j += 2
            continue
        # bare boolean flag
        j += 1
    if j < len(tokens) and tokens[j] == 'grep':
        tokens = tokens[j:]
        first = tokens[0]
if first in GREP_FAMILY:
    pattern, target = extract_grep_family(tokens, first)
    if not pattern:
        _other()
    emit(tool_name, 'grep-family', pattern, target, cwd)
    sys.exit(0)

if first == 'find':
    kind, pat, target = extract_find_name(tokens)
    if kind is None:
        _other()
    emit(tool_name, kind, pat, target, cwd)
    sys.exit(0)

_other()
" 2>/dev/null)

# Malformed JSON or parse failure → fail open
[ -z "$PARSED" ] && exit 0

TOOL_NAME=$(echo "$PARSED" | sed -n '1p')
KIND=$(echo "$PARSED"      | sed -n '2p')
PATTERN_FIELD=$(echo "$PARSED" | sed -n '3p')
TARGET_PATH=$(echo "$PARSED"   | sed -n '4p')
CWD_FIELD=$(echo "$PARSED"     | sed -n '5p')

# Phase 57 G3: only match Context Mode ctx_execute (plugin form OR legacy MCP-server
# form). Plugin form listed first per ordering rule; trigger behavior identical.
# Layer 3 of 3 — keep in lockstep with _ACCEPTED above and the setup.sh matcher.
case "$TOOL_NAME" in
    mcp__plugin_context-mode_context-mode__ctx_execute) ;;
    mcp__plugin_context-mode_context-mode__ctx_execute_file) ;;
    mcp__plugin_context-mode_context-mode__ctx_batch_execute) ;;
    mcp__context-mode__ctx_execute) ;;
    mcp__context-mode__ctx_execute_file) ;;
    mcp__context-mode__ctx_batch_execute) ;;
    *) exit 0 ;;
esac

# Fail-open for anything other than a classified code-search kind
case "$KIND" in
    grep-family|find-name|compound-search) ;;
    *) exit 0 ;;
esac

# --- Determine the SESSION's project root ---
#
# Previously this walked up from the search TARGET with a bare
# `git -C <target> rev-parse --show-toplevel`. In a submodule that returns the
# SUBMODULE root, while the session writes /tmp/cmm-session-ready-<hash> for the
# MONOREPO root — the hashes never match, the sentinel looks absent, and the gate
# fails open.
#
# Measured 2026-09-04 in a submodule monorepo (every apps/* and mcp-server a
# submodule): a source grep at apps/webapp/src/ sailed through, while docs/ and
# `.` were blocked. Planting the submodule's own sentinel flipped it to blocked,
# which is what identified the mismatch. Net effect: enforcement inert across the
# whole codebase while still firing at the root, so it looked armed.
#
# The right question is "is THIS SESSION's project indexed?", not "is the
# target's repo indexed?" — so use the shared resolver, which already handles
# nested submodules, git worktrees (via git-common-dir) and orphaned
# .git/modules trees, and caches the answer.
_PRLIB=""
for _d in "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    [ -f "$_d/project-root.sh" ] && { _PRLIB="$_d/project-root.sh"; break; }
done
# Partial install -> cannot tell -> fail open. Never block on our own absence.
[ -n "$_PRLIB" ] || exit 0
# project-root.sh resolves from $(pwd). The hook's own cwd is normally the
# session cwd, but the payload states it explicitly — honour the declared value
# so resolution does not depend on how the hook happens to be invoked.
_ORIG_PWD="$(pwd)"
if [ -n "$CWD_FIELD" ] && [ -d "$CWD_FIELD" ]; then
    cd "$CWD_FIELD" 2>/dev/null || true
fi
# shellcheck disable=SC1090
source "$_PRLIB"
cd "$_ORIG_PWD" 2>/dev/null || true
REPO_ROOT="$PROJECT_ROOT"

# Resolve the target so the non-code-dir exemptions below can inspect it, and so
# a target OUTSIDE this project can be released: our sentinel says nothing about
# another repo's index.
if [ -n "$TARGET_PATH" ]; then
    case "$TARGET_PATH" in
        /*) _ABS="$TARGET_PATH" ;;
        *)  _ABS="${CWD_FIELD%/}/$TARGET_PATH" ;;
    esac
    if [ ! -e "$_ABS" ]; then
        # Absolute target that doesn't exist -> don't misattribute to this repo (QA m1).
        case "$TARGET_PATH" in
            /*) exit 0 ;;
        esac
    else
        _RESOLVED="$(cd "$(dirname "$_ABS")" 2>/dev/null && pwd -P)/$(basename "$_ABS")"
        case "$_RESOLVED" in
            "$REPO_ROOT"|"$REPO_ROOT"/*) ;;   # inside this project — gate it
            *) exit 0 ;;                      # another repo entirely — fail open
        esac
    fi
fi
_PROBE_DIR="$REPO_ROOT"

# Exempt non-code dirs anywhere in the probe path
case "$_PROBE_DIR" in
    */node_modules/*|*/dist/*|*/build/*|*/.git/*|*/vendor/*|*/target/*) exit 0 ;;
esac
case "$TARGET_PATH" in
    */node_modules/*|*/dist/*|*/build/*|*/.git/*|*/vendor/*|*/target/*|node_modules/*|dist/*|build/*|.git/*|vendor/*|target/*) exit 0 ;;
esac

# REPO_ROOT is already the resolved session project root (from project-root.sh).
# It is deliberately NOT re-derived from the target here — that re-derivation was
# the submodule bug described above.
[ -z "$REPO_ROOT" ] && exit 0

# --- CMM availability check (.mcp.json cascade) ---
_CMMREG_LIB=""
for _d in "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    [ -f "$_d/cmm-registered.sh" ] && { _CMMREG_LIB="$_d/cmm-registered.sh"; break; }
done
# Cannot determine availability -> fail open. Never block on our own absence.
[ -n "$_CMMREG_LIB" ] || exit 0
# shellcheck disable=SC1090
source "$_CMMREG_LIB"

CMM_FOUND=false
cmm_is_registered "$REPO_ROOT" && CMM_FOUND=true
# If CMM not registered anywhere, fail open
[ "$CMM_FOUND" = false ] && exit 0

# --- Indexed-repo sentinel probe ---
# PROJECT_HASH / CMM_SENTINEL come from project-root.sh, so they are derived from
# the same root the session-start hook used when it wrote the sentinel. Computing
# them here from a locally-derived root is what let the hashes diverge.
[ -z "${PROJECT_HASH:-}" ] && exit 0
# If project not indexed for this session, fail open
[ ! -f "$CMM_SENTINEL" ] && exit 0

# --- REPLACE WITH classifier (duplicated verbatim from grep-cmm-gate.sh per 46-CONTEXT.md §Open) ---
IS_IDENTIFIER=false
if [[ "$PATTERN_FIELD" =~ ^[A-Za-z_][A-Za-z0-9_]{2,63}$ ]]; then
    case "$PATTERN_FIELD" in
      *\|*|*.*|*\**|*\+*|*\?*|*\[*|*\(*|*\)*|*\\*|*\^*|*\$*) ;;
      *) IS_IDENTIFIER=true ;;
    esac
fi

# project= is REQUIRED on both tools, and search_code takes `pattern`, not
# `query` -- see cmm_project_name() in hooks/lib/cmm-registered.sh. Omit the
# argument when the root is unknown rather than emitting project="".
_PROJ="$(cmm_project_name 2>/dev/null)"
_P=""
[ -n "$_PROJ" ] && _P=", project=\"${_PROJ}\""

if [ "$IS_IDENTIFIER" = true ]; then
    FIRST_LINE="REPLACE WITH: mcp__codebase-memory-mcp__search_graph(name_pattern=\"${PATTERN_FIELD}\"${_P})"
    SECOND_LINE="OR:           mcp__codebase-memory-mcp__search_code(pattern=\"${PATTERN_FIELD}\"${_P})"
else
    FIRST_LINE="REPLACE WITH: mcp__codebase-memory-mcp__search_code(pattern=\"${PATTERN_FIELD}\"${_P})"
    SECOND_LINE="OR:           mcp__codebase-memory-mcp__search_graph(name_pattern=\"${PATTERN_FIELD}\"${_P})"
fi

# --- Compound payload: warn, do not block ---
# Delivered as additionalContext JSON on stdout: on exit 0, stderr never reaches
# the model, so a stderr warning would be a warning nobody reads.
if [ "$KIND" = "compound-search" ]; then
    _MSG="[ctx-execute-cmm-nudge] This payload searches source in a CMM-indexed repo. Allowed, but the graph is usually faster and exact:
${FIRST_LINE}
${SECOND_LINE}
search_code covers every indexed text file (.md, .cgi and config included). grep remains right for files CMM does not index (binaries, extensionless Dockerfile-* variants, .txt, excluded dirs); use Glob to find files by name."
    python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":sys.argv[1]}}))' "$_MSG" 2>/dev/null
    exit 0
fi

# --- Block message (stderr, exit 2) ---
# Bypass last and scoped to non-code: see the note in cmm-grep-nudge.sh.
cat >&2 <<EOF
[ctx-execute-cmm-nudge] BLOCKED -- source-code search via ctx_execute in indexed repo.
${FIRST_LINE}
${SECOND_LINE}
(Non-code target -- a build artifact or a non-indexed path? Add '# cmm-exempt'
to your code. Not for searching source.)
EOF

# --- Block counter (best-effort, parity with siblings) ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "ctx_execute" 2>/dev/null || true

exit 2
