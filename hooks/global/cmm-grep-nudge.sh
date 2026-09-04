#!/bin/bash
# cmm-grep-nudge.sh — PreToolUse:Grep+Bash hook (hard-blocking CMM navigation gate)
# BLOCKING: exits 2 for code-targeted Grep or Bash navigation commands when CMM is
# available, redirecting to graph tools. Honors # cmm-exempt override in Bash commands.
#
# Install: cp hooks/global/cmm-grep-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-grep-nudge.sh
# Register in ~/.claude/settings.json under both Grep and Bash matchers:
#   "hooks": { "PreToolUse": [
#     { "matcher": "Grep", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-grep-nudge.sh"}] },
#     { "matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-grep-nudge.sh"}] }
#   ]}

# --- Shared registration probe ---
# Sourced ONCE here because this hook has TWO availability cascades (the Bash
# branch below and the Grep branch further down). They previously drifted: the
# Bash one never received a fix the Grep one got, leaving Bash navigation
# fail-open while Grep blocked — a half-armed gate.
_CMMREG_LIB=""
for _d in "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
  [ -f "$_d/cmm-registered.sh" ] && { _CMMREG_LIB="$_d/cmm-registered.sh"; break; }
done
# Cannot determine availability -> fail open. Never block on our own absence.
[ -n "$_CMMREG_LIB" ] || exit 0
# shellcheck disable=SC1090
source "$_CMMREG_LIB"

# --- Input Parsing ---
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('tool_name','') or '')
" 2>/dev/null)

# --- Bash navigation block ---
# When invoked for a Bash tool call: check for code-navigation commands against source paths.
# Only enforced when CMM sentinel is present (fail-open when CMM not indexed).
if [ "$TOOL_NAME" = "Bash" ]; then
  BASH_CMD=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('tool_input',{}).get('command','') or '')
" 2>/dev/null)

  # # cmm-exempt in command string bypasses the block
  if echo "$BASH_CMD" | grep -q '# cmm-exempt'; then
    exit 0
  fi
fi

# --- Recovery-message helpers (shared by the Bash and Grep branches) ---
# The block message is the whole product of a gate. A gate that names the exact
# call to run converts far better than one that prints a "..." placeholder, so
# these substitute the real search term wherever it can be recovered.

# _extract_term <command-or-pattern> -> a best-effort search term, possibly empty.
# Prefers the first quoted string (grep -n "reqStatus" foo.pl), else the first
# non-flag, non-path token after the navigation verb.
_extract_term() {
  local s="$1" t=""
  t=$(printf '%s' "$s" | sed -nE "s/.*'([^']{2,64})'.*/\1/p" | head -1)
  [ -z "$t" ] && t=$(printf '%s' "$s" | sed -nE 's/.*"([^"]{2,64})".*/\1/p' | head -1)
  if [ -z "$t" ]; then
    t=$(printf '%s' "$s" | sed -nE 's/.*(^|[[:space:]|;&(])(grep|rg)[[:space:]]+((-[^[:space:]]+[[:space:]]+)*)([^-[:space:]][^[:space:]]*).*/\5/p' | head -1)
    case "$t" in */*) t="" ;; esac   # a path, not a search term
  fi
  printf '%s' "$t"
}

# _cmm_recovery_lines <term> -> the two-or-three CMM call lines for the message.
# An identifier-shaped term goes to search_graph first (it resolves definitions);
# anything with regex metacharacters goes to search_code first.
_cmm_recovery_lines() {
  local term="$1"
  if [ -z "$term" ]; then
    printf '%s\n%s\n%s' \
      '  - Symbol search:  mcp__codebase-memory-mcp__search_graph(name_pattern="...")' \
      '  - Text search:    mcp__codebase-memory-mcp__search_code(query="...")' \
      '  - Fetch source:   mcp__codebase-memory-mcp__get_code_snippet(qualified_name="...")'
    return
  fi
  local is_ident=false
  if printf '%s' "$term" | grep -qE '^[A-Za-z_][A-Za-z0-9_:]{1,63}$'; then is_ident=true; fi
  if [ "$is_ident" = true ]; then
    printf '%s\n%s' \
      "  - Symbol search:  mcp__codebase-memory-mcp__search_graph(name_pattern=\"${term}\")" \
      "  - Text search:    mcp__codebase-memory-mcp__search_code(query=\"${term}\")"
  else
    printf '%s\n%s' \
      "  - Text search:    mcp__codebase-memory-mcp__search_code(query=\"${term}\")" \
      "  - Symbol search:  mcp__codebase-memory-mcp__search_graph(name_pattern=\"${term}\")"
  fi
}

# _perl_note <text> -> a Perl reassurance line when the blocked target is Perl.
# Observed failure mode: an agent blocked on `grep --include='*.pm' Foo::Bar .`
# reads a generic message, concludes CMM cannot search Perl, and falls back to
# Read. Perl IS a Hybrid LSP language here; say so at the moment of blocking,
# because that is the only moment the agent is asking the question.
_perl_note() {
  case "$1" in
    *.pl*|*.pm*|*perl*|*Perl*)
      printf '\n%s' "  Perl is fully indexed (Hybrid LSP): packages, @ISA / use parent inheritance,
  Exporter import maps and bless self-type inference all resolve. Use the graph." ;;
  esac
}

if [ "$TOOL_NAME" = "Bash" ]; then

  # Only block when command is a navigation verb against a source path.
  # Inspect only the command HEAD, dropping the two constructs whose trailing text
  # is CONTENT/DESTINATION rather than a navigation argument:
  #   - output redirection (`>`, `>>`): everything from the first `>` is a write
  #     target, not a path being searched. `cat > x.gd <<'EOF' ... EOF` false-
  #     positived because the verb (cat) matched and a path token in the written
  #     body matched the source-path regex.
  #   - heredoc (`<<`): the body is written content, not a search target.
  # We cut at the first `>` and the first `<<` ONLY — NOT a bare single `<`. A bare
  # `<` is an input redirect or process substitution (`grep foo < src/x`,
  # `diff <(cat src/a.py)`) whose path IS real navigation and must still block
  # (QA round 1, F-01). `2>/dev/null` is safe: the source path precedes the `2>`,
  # so it survives in the head.
  BNAV_HEAD="${BASH_CMD%%>*}"
  BNAV_HEAD="${BNAV_HEAD%%<<*}"
  # Match the nav verb only in COMMAND position — at the start of the command or
  # right after a separator (whitespace, |, ;, &, '(') and followed by whitespace
  # or end. A bare regex like `(grep|...)` matched the verb as a SUBSTRING of an
  # argument (e.g. `git add hooks/global/cmm-grep-nudge.sh` matched "grep" inside
  # the filename, and "headers"/"catalog" would match head/cat), false-positiving
  # on commands that merely name such a file. The path regex stays substring-based
  # (path fragments legitimately appear mid-argument).
  # A verb in PIPE-SINK position consumes upstream stdout; it is not navigation
  # against a path, and CMM has no replacement to offer for it. Measured
  # 2026-09-03: `git log --oneline | cat` and `git diff --stat | cat` were blocked
  # as "code search" because the character before `cat` is a SPACE, which the
  # separator class below matches — dropping `|` from that class would fix
  # nothing. Neutralize the sink occurrence first. The pipeline HEAD, which is
  # what actually names paths (`cat src/a.py | grep foo`), still matches normally.
  # Quoted pipes are safe: `grep 'a|b' src/x` leaves `b` unmatched, and
  # `grep 'a|cat' src/x` fails the trailing-whitespace requirement.
  BNAV_SCAN=$(printf '%s ' "$BNAV_HEAD" | sed -E 's/\|[[:space:]]*(grep|rg|find|cat|head|tail|wc)[[:space:]]/| _sink_ /g')
  if echo "$BNAV_SCAN" | grep -qE '(^|[[:space:]|;&(])(grep|rg|find|cat|head|tail|wc)([[:space:]]|$)' && echo "$BNAV_HEAD" | grep -qE '(src/|app/|apps/|lib/|pkg/|internal/|hooks/|agents/|scripts/)'; then

    # CMM availability check for Bash block (fail-open if CMM not configured)
    BASH_CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
    # Normalize path to resolve symlinks (macOS /var/folders -> /private/var/folders)
    BASH_REPO_ROOT=$(cd "${BASH_CWD:-.}" 2>/dev/null && pwd -P) || BASH_REPO_ROOT="${BASH_CWD:-.}"
    BASH_CMM_FOUND=false
    cmm_is_registered "$BASH_REPO_ROOT" && BASH_CMM_FOUND=true

    # Only block when CMM sentinel is present (index is ready)
    BASH_PROJECT_HASH=$(echo "$BASH_REPO_ROOT" | md5 -q 2>/dev/null || echo "$BASH_REPO_ROOT" | md5sum | awk '{print $1}')
    BASH_SENTINEL="/tmp/cmm-session-ready-${BASH_PROJECT_HASH}"
    if [ "$BASH_CMM_FOUND" = true ] && [ -f "$BASH_SENTINEL" ] && ! grep -q '^stale$' "$BASH_SENTINEL" 2>/dev/null; then
      # Name the CONCRETE call, not a template. Measured 2026-09-03: gates that
      # name a specific replacement convert 36-50% of blocks; gates that leave a
      # "..." placeholder convert 13-25%, and gates naming no alternative ~0%,
      # sending 90-95% of blocks straight back to Read/Bash.
      _TERM=$(_extract_term "$BASH_CMD")
      cat >&2 <<EOF
BLOCKED: Use CMM tools instead of Bash navigation for code search.
$(_cmm_recovery_lines "$_TERM")$(_perl_note "$BASH_CMD")
Add # cmm-exempt to the command to bypass this gate.
See skill \`cmm-rules\` for the full protocol.
EOF
      bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "bash-nav" 2>/dev/null || true
      exit 2
    fi
  fi
  exit 0
fi

PARSED=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ti=d.get('tool_input',{})
glob_field=ti.get('glob','') or ''
type_field=ti.get('type','') or ''
path_field=ti.get('path','') or ''
pattern_field=ti.get('pattern','') or ''
print(glob_field)
print(type_field)
print(path_field)
print(pattern_field)
" 2>/dev/null)

GLOB_FIELD=$(echo "$PARSED" | sed -n '1p')
TYPE_FIELD=$(echo "$PARSED" | sed -n '2p')
PATH_FIELD=$(echo "$PARSED" | sed -n '3p')
PATTERN_FIELD=$(echo "$PARSED" | sed -n '4p')

# --- Exception: Planning/Config Paths (check path early) ---
case "$PATH_FIELD" in
  */.vbw-planning/*|*/.planning/*|*/.claude/*|*/node_modules/*|*/.git/*) exit 0 ;;
esac

# --- CMM Availability Check (safety valve — don't block if CMM isn't configured) ---
# Determine repo root from path field or cwd
if [ -n "$PATH_FIELD" ] && [ -d "$PATH_FIELD" ]; then
  REPO_ROOT=$(git -C "$PATH_FIELD" rev-parse --show-toplevel 2>/dev/null)
elif [ -n "$PATH_FIELD" ] && [ -f "$PATH_FIELD" ]; then
  REPO_ROOT=$(git -C "$(dirname "$PATH_FIELD")" rev-parse --show-toplevel 2>/dev/null)
fi
if [ -z "$REPO_ROOT" ]; then
  CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
  REPO_ROOT="${CWD:-.}"
fi

CMM_FOUND=false
cmm_is_registered "$REPO_ROOT" && CMM_FOUND=true
# If CMM not found anywhere, allow Grep (fail open)
[ "$CMM_FOUND" = false ] && exit 0

# --- Extra extensions cache (from .codebase-memory.json) ---
# Repo-specific source extensions (.cgi is the motivating case) are known to
# neither this hook's built-in list nor CMM itself; both learn them only from
# `extra_extensions` in a repo-root .codebase-memory.json. The two therefore
# agree, and a repo without that file fails open consistently — CMM does not
# index those files and the gate does not claim them.
#
# The cache key includes the config's mtime. Keying on REPO_ROOT alone made the
# first read permanent: adding .cgi to .codebase-memory.json had no effect until
# the /tmp file was manually deleted, so the gate kept using a months-old
# extension list while CMM used the new one.
_EXT_CACHE=""
if [ -n "$REPO_ROOT" ]; then
  _CMM_CFG="${REPO_ROOT}/.codebase-memory.json"
  _CFG_MTIME=$(stat -f %m "$_CMM_CFG" 2>/dev/null || stat -c %Y "$_CMM_CFG" 2>/dev/null || echo 0)
  _EXT_CACHE="/tmp/cmm-user-ext-$(echo -n "$REPO_ROOT" | md5 -q 2>/dev/null || echo -n "$REPO_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1)-${_CFG_MTIME}"
  if [ ! -f "$_EXT_CACHE" ]; then
    python3 -c "
import json, os
for p in ['${REPO_ROOT}/.codebase-memory.json']:
    if os.path.isfile(p):
        try:
            for ext in json.load(open(p)).get('extra_extensions',{}):
                print(ext)
        except: pass
" 2>/dev/null > "$_EXT_CACHE" || rm -f "$_EXT_CACHE"
  fi
fi

# Helper: check if a filename matches code extensions (inline list + extra_extensions)
_is_code_file() {
  local f="$1"
  case "$f" in
    *.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.cxx|*.c|*.h|*.hpp|\
    *.cs|*.php|*.lua|*.scala|*.kt|*.rb|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|*.hs|\
    *.swift|*.dart|*.pl|*.pm|*.groovy|*.erl|*.r|*.R|*.clj|*.fs|*.jl|*.el|*.cu|\
    *.sql|*.vue|*.svelte|*.graphql|*.proto|*.ml|*.m|*.mm|*.nix|*.elm|*.lean|\
    *.f90|*.f95|*.f03|*.f08|*.cuh|*.v|*.sv|*.glsl|*.frag|*.vert)
      return 0 ;;
  esac
  if [ -n "$_EXT_CACHE" ] && [ -s "$_EXT_CACHE" ]; then
    local bn; bn=$(basename "$f")
    while IFS= read -r _ext; do
      case "$bn" in *"$_ext") return 0 ;; esac
    done < "$_EXT_CACHE"
  fi
  return 1
}

SHOULD_BLOCK=false
BLOCK_TARGET=""

# --- Check glob field for code extensions ---
if [ -n "$GLOB_FIELD" ]; then
  _GLOB_MATCHED=false
  # Handle brace-expansion globs like *.{ts,tsx}
  if echo "$GLOB_FIELD" | grep -q '{.*}'; then
    _BRACE_CONTENT=$(echo "$GLOB_FIELD" | sed 's/.*{\(.*\)}.*/\1/')
    IFS=',' read -ra _EXTS <<< "$_BRACE_CONTENT"
    for _EXT in "${_EXTS[@]}"; do
      if _is_code_file "file.$_EXT"; then _GLOB_MATCHED=true; break; fi
    done
  fi
  # Standard glob: extract extension suffix
  if [ "$_GLOB_MATCHED" = false ]; then
    _GLOB_SUFFIX="${GLOB_FIELD##*\*}"
    if [ -n "$_GLOB_SUFFIX" ] && [ "$_GLOB_SUFFIX" != "$GLOB_FIELD" ]; then
      _is_code_file "file${_GLOB_SUFFIX}" && _GLOB_MATCHED=true
    fi
  fi
  if [ "$_GLOB_MATCHED" = true ]; then
    SHOULD_BLOCK=true
    BLOCK_TARGET="glob='$GLOB_FIELD'"
  fi
fi

# --- Check type field for code types ---
if [ "$SHOULD_BLOCK" = false ] && [ -n "$TYPE_FIELD" ]; then
  case "$TYPE_FIELD" in
    py|python|go|js|jsx|ts|tsx|rust|java|cpp|c|cs|csharp|php|lua|scala|kotlin|\
    rb|ruby|sh|bash|zsh|zig|elixir|haskell|swift|dart|perl|groovy|erlang|r|\
    clojure|fsharp|julia|elisp|cuda|sql|vue|svelte|graphql|protobuf|ocaml|\
    objc|nix|elm|lean|fortran|verilog|glsl)
      SHOULD_BLOCK=true
      BLOCK_TARGET="type='$TYPE_FIELD'" ;;
  esac
fi

# --- Check path field for specific code file (only if glob/type not set) ---
if [ "$SHOULD_BLOCK" = false ] && [ -z "$GLOB_FIELD" ] && [ -z "$TYPE_FIELD" ] && [ -n "$PATH_FIELD" ]; then
  if _is_code_file "$PATH_FIELD"; then
    SHOULD_BLOCK=true
    BLOCK_TARGET="path='$(basename "$PATH_FIELD")'"
  fi
fi

# --- Allow if no code target detected ---
[ "$SHOULD_BLOCK" = false ] && exit 0

# --- Block: Redirect to CMM search tools (stderr, exit 2) ---
# PATTERN_FIELD is the term the agent was actually looking for; substituting it
# turns a form to fill in into a call to run. Perl targets get an extra line --
# see _perl_note.
cat >&2 <<EOF
BLOCKED: Use CMM tools instead of Grep for code search on $BLOCK_TARGET.
$(_cmm_recovery_lines "$PATTERN_FIELD")
  - Trace callers:  mcp__codebase-memory-mcp__trace_path$(_perl_note "$GLOB_FIELD $TYPE_FIELD $PATH_FIELD")
  Grep is allowed for: non-code files (JSON, YAML, Markdown, config, env)
See skill \`cmm-rules\` for the full protocol.
EOF

# --- Block Counter ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "grep" 2>/dev/null || true

exit 2
