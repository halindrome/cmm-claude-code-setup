#!/bin/bash
# ctx-execute-cmm-nudge.sh — PreToolUse hook: hard-block source-code search laundered through mcp__context-mode__ctx_execute in indexed CMM repos.
# BLOCKING: exits 2 when tool_input.code is an unambiguous grep/rg/ack/ag/ugrep/find-name against an indexed project path; otherwise exits 0 (fail-open on any ambiguity).
#
# Install: cp hooks/project/ctx-execute-cmm-nudge.sh .claude/hooks/ && chmod +x .claude/hooks/ctx-execute-cmm-nudge.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "mcp__context-mode__ctx_execute", "hooks": [{"type": "command", "command": "bash .claude/hooks/ctx-execute-cmm-nudge.sh"}] }] }
# Matcher: PreToolUse:mcp__context-mode__ctx_execute
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
import sys, json, re, shlex

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
code = ti.get('code','') or ''
cwd = d.get('cwd','') or ''

if tool_name != 'mcp__context-mode__ctx_execute':
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

if not is_simple_single_statement(code):
    emit(tool_name, 'other', '', '', cwd)
    sys.exit(0)

line = [l for l in code.strip().splitlines() if l.strip() and not l.strip().startswith('#')][0]

# Tokenize respecting quotes
try:
    tokens = shlex.split(line, posix=True)
except Exception:
    emit(tool_name, 'other', '', '', cwd)
    sys.exit(0)

if not tokens:
    emit(tool_name, 'other', '', '', cwd)
    sys.exit(0)

first = tokens[0]
GREP_FAMILY = {'grep','rg','ack','ag','ugrep'}

def extract_grep_family(toks):
    # First non-flag positional arg is the pattern; last remaining positional is target path.
    positionals = []
    i = 1
    skip_next = False
    # Flags that take a value (common subset) — conservatively treat all -X with a next token
    # starting with non-dash as an option-with-value is too aggressive; instead recognize a
    # small known set. Anything unknown just follows default: flags start with '-', non-flags
    # are positional. For bundled '-rn', '-e <pat>' the '-e' case needs handling.
    value_flags = {'-e','--regexp','-f','--file','--include','--exclude','--exclude-dir','-m','--max-count','-A','--after-context','-B','--before-context','-C','--context','-g','--glob','-t','--type','--type-add','-r','--replace','-o'}
    # Note: for rg/ack/ag, -r means recursive for grep but replace for rg. We treat -r ambiguously
    # as a value-taking flag only when the tool is rg. For grep, -r is boolean.
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

if first in GREP_FAMILY:
    pattern, target = extract_grep_family(tokens)
    if not pattern:
        emit(tool_name, 'other', '', '', cwd)
        sys.exit(0)
    emit(tool_name, 'grep-family', pattern, target, cwd)
    sys.exit(0)

if first == 'find':
    kind, pat, target = extract_find_name(tokens)
    if kind is None:
        emit(tool_name, 'other', '', '', cwd)
        sys.exit(0)
    emit(tool_name, kind, pat, target, cwd)
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

# Only match mcp__context-mode__ctx_execute — every other tool is a no-op
[ "$TOOL_NAME" != "mcp__context-mode__ctx_execute" ] && exit 0

# Fail-open for anything other than a classified code-search kind
case "$KIND" in
    grep-family|find-name) ;;
    *) exit 0 ;;
esac

# --- Determine repo root (walk upward from target or cwd) ---
REPO_ROOT=""
_PROBE_DIR=""
if [ -n "$TARGET_PATH" ]; then
    # Resolve relative target against cwd
    case "$TARGET_PATH" in
        /*) _ABS="$TARGET_PATH" ;;
        *)  _ABS="${CWD_FIELD%/}/$TARGET_PATH" ;;
    esac
    if [ -d "$_ABS" ]; then
        _PROBE_DIR="$_ABS"
    elif [ -f "$_ABS" ]; then
        _PROBE_DIR="$(dirname "$_ABS")"
    else
        # Path doesn't exist on disk — fall back to cwd for repo detection
        _PROBE_DIR="$CWD_FIELD"
    fi
else
    _PROBE_DIR="$CWD_FIELD"
fi

# Exempt non-code dirs anywhere in the probe path
case "$_PROBE_DIR" in
    */node_modules/*|*/dist/*|*/build/*|*/.git/*|*/vendor/*|*/target/*) exit 0 ;;
esac
case "$TARGET_PATH" in
    */node_modules/*|*/dist/*|*/build/*|*/.git/*|*/vendor/*|*/target/*|node_modules/*|dist/*|build/*|.git/*|vendor/*|target/*) exit 0 ;;
esac

if [ -n "$_PROBE_DIR" ] && [ -d "$_PROBE_DIR" ]; then
    REPO_ROOT=$(git -C "$_PROBE_DIR" rev-parse --show-toplevel 2>/dev/null)
    [ -z "$REPO_ROOT" ] && REPO_ROOT="$_PROBE_DIR"
fi
[ -z "$REPO_ROOT" ] && exit 0

# --- CMM availability check (.mcp.json cascade) ---
CMM_FOUND=false
if [ -f "$REPO_ROOT/.mcp.json" ] && grep -q 'codebase-memory-mcp' "$REPO_ROOT/.mcp.json" 2>/dev/null; then
    CMM_FOUND=true
fi
if [ "$CMM_FOUND" = false ]; then
    CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    if [ -f "$CLAUDE_SETTINGS" ] && grep -q 'codebase-memory-mcp' "$CLAUDE_SETTINGS" 2>/dev/null; then
        CMM_FOUND=true
    fi
fi
# If CMM not registered anywhere, fail open
[ "$CMM_FOUND" = false ] && exit 0

# --- Indexed-repo sentinel probe ---
PROJECT_HASH=$(echo "$REPO_ROOT" | md5 -q 2>/dev/null || echo "$REPO_ROOT" | md5sum 2>/dev/null | awk '{print $1}')
[ -z "$PROJECT_HASH" ] && exit 0
CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"
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

if [ "$IS_IDENTIFIER" = true ]; then
    FIRST_LINE="REPLACE WITH: mcp__codebase-memory-mcp__search_graph(name_pattern=\"${PATTERN_FIELD}\")"
    SECOND_LINE="OR:           mcp__codebase-memory-mcp__search_code(query=\"${PATTERN_FIELD}\")"
else
    FIRST_LINE="REPLACE WITH: mcp__codebase-memory-mcp__search_code(query=\"${PATTERN_FIELD}\")"
    SECOND_LINE="OR:           mcp__codebase-memory-mcp__search_graph(name_pattern=\"${PATTERN_FIELD}\")"
fi

# --- Block message (stderr, exit 2) ---
cat >&2 <<EOF
[ctx-execute-cmm-nudge] BLOCKED -- source-code search via ctx_execute in indexed repo.
${FIRST_LINE}
${SECOND_LINE}
Bypass: add '# cmm-exempt' to your code, or run against a non-indexed / build-artifact path.
EOF

# --- Block counter (best-effort, parity with siblings) ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "ctx_execute" 2>/dev/null || true

exit 2
