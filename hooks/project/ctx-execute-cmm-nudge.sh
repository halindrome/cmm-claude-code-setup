#!/bin/bash
# ctx-execute-cmm-nudge.sh — PreToolUse hook: hard-block source-code search laundered through ctx_execute in indexed CMM repos (plugin-form and MCP-server-form coverage).
# BLOCKING: exits 2 when tool_input.code is an unambiguous grep/rg/ack/ag/ugrep/find-name against an indexed project path; otherwise exits 0 (fail-open on any ambiguity).
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
# Parser classifies every ; && || newline-separated command (pipeline heads only) and gates on any search that is not released; heredoc bodies are skipped, $(...) segments fail open.

# --- Input Parsing ---
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Parse JSON + classify the code field in one python3 block.
# Output (one per line):
#   1: tool_name
#   2: kind (grep-family | find-name | read | other | empty)
#   3: pattern (extracted search term; empty when kind=other/empty)
#   4: target_path (extracted last positional arg, or empty)
#   5: cwd
PARSED=$(echo "$INPUT" | python3 -c "
import sys, json, os, re, shlex

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

# Every batch command is segmented below, so one grep hidden among several
# batch commands is still caught.
code = chr(10).join(_cmds)

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

# Only shell is parsed as shell. A Python line 'rg = re.compile(...)' or Perl's
# builtin grep at the start of a statement read as a search command and blocked
# with a nonsense REPLACE WITH (QA round 2 R2-01). Batch commands are always
# shell. Same scope as ctx-payload-guard.sh.
if not tool_name.endswith('ctx_batch_execute') and (ti.get('language') or 'shell').lower() not in ('shell', 'bash', 'sh', 'zsh'):
    emit(tool_name, 'other', '', '', cwd)
    sys.exit(0)

# Segment parser. This used to accept only a single pipe-less statement and fail
# open on anything else -- which is how agents actually write sandbox searches.
# Observed 2026-10-14: a subagent blocked on a Bash grep re-issued it as
# ctx_execute('cd apps; for a in ...; do grep -rnE ... | grep -v spec; done')
# 26 times, and every call sailed through. Now every command separated by
# ; && || or a newline is classified. Only a pipeline HEAD counts: a grep after
# a pipe filters upstream output, it searches nothing.
# Heredoc bodies are content, not commands, and are skipped (strip_heredocs).
# Still fail open: \$(...) / backtick subshells (that segment only).
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

def strip_heredocs(s):
    # A heredoc body is content, not commands: drop it, keep classifying the
    # rest. This used to fail open for the WHOLE payload on any <<, so writing
    # a file first (cat > f <<EOF ... EOF; grep -rn Foo src/) disarmed the gate,
    # and so did arithmetic like 1<<2 (QA round 1 F-06). A << whose terminator
    # never appears is not a heredoc and is left alone.
    lines = s.split(chr(10))
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        out.append(ln)
        i += 1
        if '<<' not in _strip_quoted(ln):
            continue
        for m in re.finditer(r'<<(-?)[ \t]*[\x27\x22]?([A-Za-z_][A-Za-z0-9_]*)', ln):
            end = next((j for j in range(i, len(lines))
                        if (lines[j].lstrip(chr(9)) if m.group(1) else lines[j]) == m.group(2)), None)
            if end is not None:
                i = end + 1
    return chr(10).join(out)

def segments(s):
    # Yields (tokens, after_pipe) per command. Lexed non-posix so a QUOTED ; or |
    # keeps its quotes and cannot pose as a separator, then re-split posix to
    # strip them. A bare & also separates, so 2>&1 leaves a stray 2> (dropped
    # below as a redirection) rather than swallowing the next command.
    s = s.replace(chr(92) + chr(10), ' ').replace(chr(10), ' ; ')
    lx = shlex.shlex(s, posix=False, punctuation_chars=';&|')
    lx.whitespace_split = True
    cur, after_pipe = [], False
    for t in list(lx) + [';']:
        if set(t) <= set(';&|'):
            yield cur, after_pipe
            cur, after_pipe = [], (t == '|')
        else:
            cur.append(t)

def git_unwrap(tokens):
    # Sub-command laundering: git <git-opts...> grep ... is still a grep invocation.
    # Skip leading git-level options (-c key=val, -C path, --git-dir=..., --work-tree=...,
    # --no-pager, -p/--paginate, --bare, --no-replace-objects, --exec-path[=...], --namespace[=...])
    # and unwrap to the subcommand. If the subcommand is grep, treat the remainder as a grep call.
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
        return tokens[j:]
    return tokens

GREP_FAMILY = {'grep','egrep','fgrep','rg','ripgrep','ack','ag','ugrep'}
NONCODE = ('.md', '.markdown', '.json', '.yaml', '.yml', '.txt', '.log', '.csv',
           '.toml', '.lock', '.ini', '.cfg', '.conf', '.xml', '.env')

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
    includes = []
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
            # --include=... attached-value form: kept only as a file filter
            if '=' in t:
                if t.startswith(('--include=', '--glob=')):
                    includes.append(t.split('=', 1)[1])
                i += 1
                continue
            # Other value-taking flags we recognize
            if t in value_flags and i+1 < len(toks):
                if t in ('--include', '-g', '--glob'):
                    includes.append(toks[i+1])
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
            return ('', '', includes)
        pattern = positionals[0]
        target = positionals[-1] if len(positionals) > 1 else ''
    return (pattern, target, includes)

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

def classify(tokens):
    first = tokens[0]
    if first == 'git':
        tokens = git_unwrap(tokens)
        first = tokens[0]
    if first in GREP_FAMILY:
        pattern, target, includes = extract_grep_family(tokens, first)
        # Restricted to non-code files by --include / -g: a config search CMM has
        # nothing to offer for. An allowlist, not 'no code extension' -- CODE_EXTS
        # lacks extra_extensions, so --include='*.cgi' must still block. A '!glob'
        # excludes rather than restricts, so it does not count.
        includes = [g for g in includes if not g.startswith('!')]
        if includes and all(g.lower().endswith(NONCODE) for g in includes):
            return None
        return ('grep-family', pattern, target) if pattern else None
    if first == 'find':
        kind, pat, target = extract_find_name(tokens)
        return (kind, pat, target) if kind else None
    return None

def read_target(tokens):
    # Line-range / whole-file reads: sed -n 'a,bp' F, head/tail [-n N] F, cat F,
    # awk 'NR>=a' F. Returns the file operand or None. sed needs -n so an
    # in-place edit (sed -i) is never mistaken for a read.
    verb = tokens[0]
    if verb not in ('sed','head','tail','cat','awk'):
        return None
    if verb == 'sed' and not any(t.startswith('-') and not t.startswith('--') and 'n' in t for t in tokens[1:]):
        return None
    pos, skip = [], False
    for t in tokens[1:]:
        if skip:
            skip = False
            continue
        if t in ('-n','-c','-e','-f','-v','-F'):
            skip = verb in ('head','tail','awk') or t in ('-e','-f')
            continue
        if t.startswith('-'):
            continue
        pos.append(t)
    if verb in ('sed','awk') and len(pos) < (1 if '-e' in tokens or '-f' in tokens else 2):
        return None
    return pos[-1] if pos else None

# A cd earlier in the payload moves where a relative target points; follow it so
# the outside-repo and non-code-dir checks see the real directory. A target that
# does not resolve (apps/\$a/src) falls back to the cd directory itself.
base = cwd
read_file = ''
hits = []
env = {}

def expand(t):
    # Candidate values for a word: itself, or every substitution of the
    # assigned / loop values of the \$NAMEs in it; [] when it references a
    # variable we never saw set.
    names = set(re.findall(r'\\\$\{?([A-Za-z_][A-Za-z0-9_]*)', t))
    if not names:
        return [] if '\$' in t else [t]
    if not names <= set(env):
        return []
    outs = [t]
    for n in names:
        rx = re.compile(r'\\\$(\{' + n + r'\}|' + n + r'(?![A-Za-z0-9_]))')
        outs = [rx.sub(lambda m, v=v: v, o) for o in outs for v in env[n]]
    return outs[:20]
try:
    segs = list(segments(strip_heredocs(code)))
except ValueError:
    segs = []   # unbalanced quotes -> cannot tell -> fail open
for raw, after_pipe in segs:
    if after_pipe or any('\$(' in t or chr(96) in t for t in raw):
        # for x in \$(find ... -name '*.ts'): the values are unknown, but a list
        # that names no file type, or any code type, is taken as files here so
        # the loop body stays gated. One that names only non-code files is not.
        if len(raw) > 3 and raw[0] == 'for' and raw[2] == 'in':
            exts = [e.lower() for e in re.findall(r'\.([A-Za-z0-9]+)\b', ' '.join(raw[3:]))]
            env[raw[1]] = [] if exts and all('.' + e in NONCODE for e in exts) else ['.']
        continue
    try:
        toks = shlex.split(' '.join(raw), posix=True)
    except ValueError:
        continue
    # Drop redirections. A detached OUTPUT operator also takes its target with
    # it: in 'grep -rn Foo src/ 2> /dev/null' the target is src/, not /dev/null
    # (QA round 1 F-05 -- the hook released on the redirect file). A bare '<' is
    # dropped alone so the file it feeds stays the grep target.
    kept, skip = [], False
    for t in toks:
        if skip:
            skip = False
        elif re.fullmatch(r'\d*>>?|&>>?|\d*>\||<<<', t):
            skip = True   # <<< feeds a string, not a file (QA round 2 R2-03)
        elif not re.match(r'^(\d*[<>]|&>)', t):
            kept.append(t)
    herestr = '<<<' in toks
    toks = kept
    # Wrapper words and a ( glued to the verb by the lexer (QA round 1 F-06).
    # Assignments are remembered so a later \$NAME target can be resolved.
    while toks and (toks[0] in ('do','then','else','elif','if','while','until','{','(','!','sudo','time','command','env') or re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', toks[0])):
        if '=' in toks[0] and toks[0][0] not in '({!':
            k, v = toks[0].split('=', 1)
            env[k] = [v]
        toks = toks[1:]
    if len(toks) > 3 and toks[0] == 'for' and toks[2] == 'in':
        env[toks[1]] = toks[3:]
        continue
    if toks and toks[0].startswith('(') and len(toks[0]) > 1:
        toks[0] = toks[0].lstrip('(')
    if toks and toks[-1].endswith(')') and not toks[-1].startswith('('):
        toks[-1] = toks[-1].rstrip(')') or toks[-1]
    if not toks:
        continue
    if toks[0] == 'cd' and len(toks) > 1:
        # An unresolvable cd (cd \$R, cd \$PWD) leaves base unknown; targets
        # then resolve against cwd rather than a path that does not exist
        # (QA round 2 R2-08).
        d = expand(toks[1])
        base = os.path.join(base or '/', d[0]) if len(d) == 1 and (base or d[0].startswith('/')) else None
        continue
    rt = read_target(toks)
    if rt and not read_file and base:
        rt = os.path.join(base, rt)
        if os.path.isfile(rt):
            read_file = rt
    hit = classify(toks)
    if hit and herestr and not hit[2]:
        hit = None   # grep FAIL <<< "\$out" searches the string, not cwd
    if hit:
        kind, pattern, target = hit
        # A \$NAME target expands to the assigned value or each loop value; one
        # that cannot be resolved (\$(mktemp), a read variable) is not a source
        # path we can name, so it is not gated (QA round 2 R2-04).
        for t in expand(target):
            if base and base != cwd and not t.startswith('/'):
                joined = os.path.join(base, t)
                t = joined if os.path.exists(joined) else (base if os.path.isdir(base) else t)
            hits.append((kind, pattern, t))

# Every search, not just the first: the shell side releases a hit whose target
# is non-code or outside the repo, so stopping at the first one let
# 'grep -n x README.md; grep -rn Foo src/' through (QA round 1 F-01). Line 2-5
# carry the first hit; each hit then follows on its own line, fields split by
# the unit separator.
if hits:
    emit(tool_name, hits[0][0], hits[0][1], hits[0][2], cwd)
    for h in hits:
        print(chr(31).join(x.replace(chr(10), ' ') for x in h))
    sys.exit(0)

# No search anywhere in the payload: a source READ is handed to the Read hook's
# soft budget below rather than blocked -- see the read branch in the shell part.
if read_file:
    emit(tool_name, 'read', '', read_file, cwd)
    sys.exit(0)

emit(tool_name, 'other', '', '', cwd)
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

# --- Source reads: advisory, via the Read hook's own budget ---
# sed -n 'a,bp' / head / tail / cat on a source file is the sandbox spelling of
# Read. Read is deliberately never blocked (cmm-nudge.sh header: the hard Read
# gate was measured net-negative, and a block just moves a bounded read to the
# Read tool -- or, for sed's multi-range form, to several of them). So hand it to
# cmm-nudge.sh as a Read of the same file: one counter per (session, file) across
# both routes, the same exemptions, the same back-off. Absent -> silent.
if [ "$KIND" = "read" ]; then
    for _n in "$(dirname "${BASH_SOURCE[0]}")/cmm-nudge.sh" "$(dirname "${BASH_SOURCE[0]}")/../global/cmm-nudge.sh"; do
        if [ -f "$_n" ]; then
            echo "$INPUT" | TARGET="$TARGET_PATH" python3 -c "
import json, os, sys
d = json.load(sys.stdin)
print(json.dumps({'tool_name': 'Read', 'tool_input': {'file_path': os.environ['TARGET']},
                  'session_id': d.get('session_id', ''), 'cwd': d.get('cwd', '')}))
" 2>/dev/null | bash "$_n" 2>/dev/null
            break
        fi
    done
    exit 0
fi

# Fail-open for anything other than a classified code-search kind
case "$KIND" in
    grep-family|find-name) ;;
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
# Absolute BEFORE the cd below: the hook is registered as a relative path
# (bash .claude/hooks/...), so when the payload cwd is a subdirectory the relative
# source failed, PROJECT_ROOT came back empty and the gate failed open.
_PRLIB="$(cd "$(dirname "$_PRLIB")" && pwd -P)/$(basename "$_PRLIB")"
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

# _released <target> -> 0 when this one search should pass, 1 when it gates.
_released() {
    local t="$1" abs resolved
    # Resolve the target so the non-code-dir exemptions below can inspect it, and
    # so a target OUTSIDE this project can be released: our sentinel says nothing
    # about another repo's index.
    if [ -n "$t" ]; then
        case "$t" in
            /*) abs="$t" ;;
            *)  abs="${CWD_FIELD%/}/$t" ;;
        esac
        if [ ! -e "$abs" ]; then
            # Absolute target that doesn't exist -> don't misattribute to this repo (QA m1).
            case "$t" in /*) return 0 ;; esac
        else
            resolved="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)/$(basename "$abs")"
            case "$resolved" in
                "$REPO_ROOT"|"$REPO_ROOT"/*) ;;   # inside this project — gate it
                *) return 0 ;;                    # another repo entirely — fail open
            esac
        fi
    fi
    case "$t" in
        */node_modules/*|*/dist/*|*/build/*|*/.git/*|*/vendor/*|*/target/*|node_modules/*|dist/*|build/*|.git/*|vendor/*|target/*) return 0 ;;
    esac
    # Non-code file targets: CMM has nothing to offer for them, and a block that
    # suggests search_graph(name_pattern=...) on CHANGELOG.md teaches agents to
    # route around the gate. Same carve-out as the Grep gate.
    case "$t" in
        *.md|*.markdown|*.json|*.yaml|*.yml|*.txt|*.log|*.csv|*.toml|*.lock|*.ini|*.cfg|*.conf|*.xml|*.env) return 0 ;;
    esac
    return 1
}

# Exempt non-code dirs anywhere in the probe path
case "$REPO_ROOT" in
    */node_modules/*|*/dist/*|*/build/*|*/.git/*|*/vendor/*|*/target/*) exit 0 ;;
esac

# Gate on the first search that is not released; its term goes in the message.
_GATED=false
while IFS=$'\x1f' read -r _k _p _t; do
    if ! _released "$_t"; then
        KIND="$_k"; PATTERN_FIELD="$_p"; TARGET_PATH="$_t"; _GATED=true
        break
    fi
done < <(printf '%s\n' "$PARSED" | sed -n '6,$p')
[ "$_GATED" = true ] || exit 0

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

# --- Block message (stderr, exit 2) ---
# No bypass marker: see the note in cmm-grep-nudge.sh.
cat >&2 <<EOF
[ctx-execute-cmm-nudge] BLOCKED -- source-code search via ctx_execute in indexed repo.
${FIRST_LINE}
${SECOND_LINE}
(Non-code files -- .json, .yaml, .md, .log, config -- are not gated: name the
file or restrict with --include='*.yaml'.)
EOF

# --- Block counter (best-effort, parity with siblings) ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "ctx_execute" 2>/dev/null || true

exit 2
