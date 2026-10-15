#!/bin/bash
# cmm-grep-nudge.sh — PreToolUse:Grep+Bash hook (hard-blocking CMM navigation gate)
# BLOCKING: exits 2 for code-targeted Grep or Bash navigation commands when CMM is
# available, redirecting to graph tools. No bypass marker -- see the block message note.
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
fi

# --- Recovery-message helpers (shared by the Bash and Grep branches) ---
# The block message is the whole product of a gate. A gate that names the exact
# call to run converts far better than one that prints a "..." placeholder, so
# these substitute the real search term wherever it can be recovered.

# _extract_term <command-or-pattern> -> a best-effort search term, possibly empty.
# Prefers the first quoted string (grep -n "reqStatus" foo.pl), else the first
# non-flag, non-path token after the navigation verb.
# _narrow_to_search_segment <command> -> the sub-command that does the searching.
#
# Compound commands are routinely narrated with echo labels:
#   git -C apps/mobile status | head -20; echo "=== spec coverage ==="; \
#   grep -n "changeTarget" apps/mobile/src/.../comms.service.spec.ts
# _extract_term takes the FIRST quoted string in the command, which here is the
# echo label — so the block correctly fired and then suggested
#   search_code(pattern="=== spec: changeTarget/_fetch coverage ===")
# a call that runs and returns nothing. Observed live 2026-09-04.
#
# Same failure class the --include='*.pl' fix already addressed: a
# plausible-but-wrong term converts worse than a bare "..." placeholder, because
# it looks correct. Narrow to the segment owning the search verb first.
#
# Splits on ; && || and newlines only — NOT on a single `|`, because a grep and
# its pipe sink belong to the same segment (`grep foo src/ | head -40`).
_narrow_to_search_segment() {
  local s="$1" seg stripped
  local nl=$'\n'
  local tmp="${s//&&/$nl}"
  tmp="${tmp//||/$nl}"
  tmp="${tmp//;/$nl}"
  while IFS= read -r seg; do
    # Strip leading whitespace, env assignments and sudo before reading the verb.
    stripped=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+//; s/^sudo[[:space:]]+//')
    case "$stripped" in
      grep\ *|egrep\ *|fgrep\ *|rg\ *|ack\ *|ag\ *|ugrep\ *|find\ *)
        printf '%s' "$seg"; return 0 ;;
    esac
    # `git grep` counts, but only when grep is the SUBCOMMAND. A bare `git -C dir
    # branch` must not win the segment: it owns no search term, so selecting it
    # yields the "..." placeholder and loses the real one further along. Peel the
    # repo/config-selection global flags, then require grep.
    if printf '%s' "$stripped" | grep -qE '^git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+|--no-pager|-c[[:space:]]+[^[:space:]]+))*[[:space:]]+grep([[:space:]]|$)'; then
        printf '%s' "$seg"; return 0
    fi
  done <<< "$tmp"
  # No segment clearly owns a search verb -> unchanged (previous behaviour).
  printf '%s' "$s"
}

_extract_term() {
  local s="$1" t=""
  # Narrow BEFORE the filter-flag strip below, so an echo label in a sibling
  # segment cannot supply the term.
  s="$(_narrow_to_search_segment "$s")"
  # Drop value-carrying filter flags BEFORE looking for a quoted term: their
  # argument is a glob or a file type, never the thing being searched for.
  # `grep -rn 'foo' src/ --include='*.pl'` must yield foo, not *.pl -- and a
  # plausible-but-wrong term is worse for conversion than the old "..."
  # placeholder, because search_graph(name_pattern="*.pl") looks correct and
  # returns nothing. That misfires hardest on the Perl case WS2 exists to fix.
  s=$(printf '%s' "$s" | sed -E "s/(--(include|exclude|exclude-dir|type|type-add|glob|iglob|file)|[[:space:]]-[tgf])(=|[[:space:]]+)('[^']*'|\"[^\"]*\"|[^[:space:]]+)/ /g")
  # `[^']*` anchors to the FIRST quoted string; a leading `.*` is greedy and
  # lands on the LAST one, which is the opposite of what the comment promises.
  t=$(printf '%s' "$s" | sed -nE "s/[^']*'([^']{2,64})'.*/\1/p" | head -1)
  [ -z "$t" ] && t=$(printf '%s' "$s" | sed -nE 's/[^"]*"([^"]{2,64})".*/\1/p' | head -1)
  if [ -z "$t" ]; then
    t=$(printf '%s' "$s" | sed -nE 's/.*(^|[[:space:]|;&(])(grep|rg)[[:space:]]+((-[^[:space:]]+[[:space:]]+)*)([^-[:space:]][^[:space:]]*).*/\5/p' | head -1)
    case "$t" in */*) t="" ;; esac   # a path, not a search term
  fi
  printf '%s' "$t"
}

# _cmm_recovery_lines <term> -> the two-or-three CMM call lines for the message.
# An identifier-shaped term goes to search_graph first (it resolves definitions);
# anything with regex metacharacters goes to search_code first.
#
# Every emitted call carries project= -- it is a REQUIRED argument on all of
# these tools, and the search term goes in search_code's `pattern`, not `query`
# (there is no `query` parameter). See cmm_project_name() in
# hooks/lib/cmm-registered.sh for why printing a call that cannot run is worse
# than printing no call at all.
_cmm_recovery_lines() {
  local term="$1"
  local proj; proj="$(cmm_project_name 2>/dev/null)"
  # Omit the argument entirely when the root is unknown; project="" fails the
  # same way a missing project does, and a visibly-empty argument reads as a
  # tool defect rather than a prompt to supply the value.
  local p=""
  [ -n "$proj" ] && p=", project=\"${proj}\""
  if [ -z "$term" ]; then
    printf '%s\n%s\n%s' \
      "  - Symbol search:  mcp__codebase-memory-mcp__search_graph(name_pattern=\"...\"${p})" \
      "  - Text search:    mcp__codebase-memory-mcp__search_code(pattern=\"...\"${p})" \
      "  - Fetch source:   mcp__codebase-memory-mcp__get_code_snippet(qualified_name=\"...\"${p})"
    return
  fi
  local is_ident=false
  if printf '%s' "$term" | grep -qE '^[A-Za-z_][A-Za-z0-9_:]{1,63}$'; then is_ident=true; fi
  if [ "$is_ident" = true ]; then
    printf '%s\n%s' \
      "  - Symbol search:  mcp__codebase-memory-mcp__search_graph(name_pattern=\"${term}\"${p})" \
      "  - Text search:    mcp__codebase-memory-mcp__search_code(pattern=\"${term}\"${p})"
  else
    printf '%s\n%s' \
      "  - Text search:    mcp__codebase-memory-mcp__search_code(pattern=\"${term}\"${p})" \
      "  - Symbol search:  mcp__codebase-memory-mcp__search_graph(name_pattern=\"${term}\"${p})"
  fi
}

# _perl_note <text> -> a Perl reassurance line when the blocked target is Perl.
# Observed failure mode: an agent blocked on `grep --include='*.pm' Foo::Bar .`
# reads a generic message, concludes CMM cannot search Perl, and falls back to
# Read. Perl IS a Hybrid LSP language here; say so at the moment of blocking,
# because that is the only moment the agent is asking the question.
_perl_note() {
  # `*.pl*` is a substring match, so it fired on .plist, .plugin.ts and .pm2 —
  # telling an agent searching a TypeScript file that Perl is indexed. Anchor
  # each extension at a word boundary instead: the extension must be followed by
  # a non-alphanumeric or end of string.
  case "$1" in
    *.pl|*.pm|*.pl[!a-zA-Z0-9]*|*.pm[!a-zA-Z0-9]*|*perl*|*Perl*)
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
  # We drop each heredoc (operator, delimiter, body -- only when its terminator
  # line exists), each here-string with its word, and each output redirection
  # WITH its target outside quotes — NOT a bare single `<`. A bare `<` is an input
  # redirect or process substitution (`grep foo < src/x`, `diff <(cat src/a.py)`)
  # whose path IS real navigation and must still block (QA round 1, F-01).
  # Cutting at the first `>` or `<<` discarded every LATER command: `echo hi >
  # /tmp/x; grep -rn Foo src/` and `x=$((1<<2)); grep -rn Foo src/` passed, and a
  # sed strip of `>` inside quotes unbalanced them (QA rounds 1-2, F-08 / R2-02 /
  # R2-07). Python missing -> the old cut, which errs toward passing.
  BNAV_HEAD=$(BNAV_CMD="$BASH_CMD" python3 -c '
import os, re
s = os.environ["BNAV_CMD"]
hd = re.compile(r"(?<!<)<<-?[ \t]*([\x22\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1")
pos = 0
while True:
    m = hd.search(s, pos)
    if not m:
        break
    eol = s.find("\n", m.end())
    term = re.compile(r"^[ \t]*" + m.group(2) + r"[ \t]*$", re.M).search(s, eol + 1) if eol >= 0 else None
    if term:
        s = s[:m.start()] + s[m.end():eol + 1] + s[term.end() + 1:]
        pos = m.start()
    else:
        pos = m.end()
# A here-string word is data, unless it runs a command: <<< "$(cat src/x)" (R3 F-09).
# Matched inside the quote-aware scan, so a quoted <<< is left alone (R3 F-04).
TOK = re.compile(r"(?P<q>\x27[^\x27]*\x27|\x22(?:\\.|[^\x22\\])*\x22|\\.)"
                 r"|(?P<hs><<<[ \t]*(?:\x22(?:\\.|[^\x22\\])*\x22|\x27[^\x27]*\x27|[^\s;|&]+))"
                 r"|(?P<rd>(?:&|\b\d+)?>>?\|?[ \t]*(?:&\d+|&-|\x22[^\x22]*\x22|\x27[^\x27]*\x27|[^\s;|&<>()]*))"
                 r"|.", re.S)
def keep(m):
    if m.lastgroup == "rd" or (m.lastgroup == "hs" and "$(" not in m.group(0)):
        return " "
    return m.group(0)[3:] if m.lastgroup == "hs" else m.group(0)
print("".join(keep(m) for m in TOK.finditer(s)))
' 2>/dev/null) || BNAV_HEAD="${BASH_CMD%%<<*}"
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
  #
  # A verb left DANGLING at the end of the head — no argument after it — owns no
  # path, so it cannot be navigation. This is what the `<<` cut above creates:
  #
  #   git -C /repo/apps/mobile commit --no-edit -m "$(cat <<'EOF' … EOF)"
  #
  # cuts to `… -m "$(cat `, and the bare `cat` (preceded by `(`, which is in the
  # separator class) then matched the verb test while `apps/` in the `git -C`
  # PATH satisfied the path test — verb and path taken from two different
  # commands. Observed live 2026-09-04 blocking a commit whose message body came
  # from a here-doc: the same shape ctx-execute-enforcer.sh was fixed for in
  # 4d26952, blocked here instead, so the fix bought the agent nothing.
  #
  # Narrow, not a heredoc special case: the invariant is that the verb and the
  # path must belong to the SAME command. `cat src/a.py` keeps its argument and
  # still blocks; `cat < src/x.py` is untouched because a bare `<` is never cut
  # (QA round 1, F-01); `echo "$(cat apps/x.ts)"` has no cut at all and blocks.
  BNAV_SCAN=$(printf '%s ' "$BNAV_HEAD" \
    | sed -E 's/\|[[:space:]]*(grep|rg|find|cat|head|tail|wc)[[:space:]]/| _sink_ /g' \
    | sed -E 's/(^|[[:space:]|;&(])(grep|rg|find|cat|head|tail|wc)[[:space:]]*$/\1_dangling_ /')
  #
  # The two greps below still take the verb and the path from the WHOLE head, so
  # `M=apps/x; cat $M/tsconfig.spec.json` or `grep FAIL /tmp/verify.log; ls apps/`
  # paired a verb from one command with a path from another. _bnav_source_segment
  # re-checks per command (quote-aware, split on ; & | and newlines): some single
  # command must hold both, and its path operands must not all be non-code files
  # (nor its --include / -g globs all non-code). Measured 2026-10-14: agents met
  # those false positives with '# cmm-exempt' and then kept the marker for real
  # source greps. Unparseable (unbalanced quotes) -> keep the block.
  _bnav_source_segment() {
    BNAV_SCAN="$1" python3 -c '
import os, re, shlex, sys
VERB = re.compile(r"(^|[\s|;&(])(grep|rg|find|cat|head|tail|wc)(\s|$)")
SRC = re.compile(r"(src/|app/|apps/|lib/|pkg/|internal/|hooks/|agents/|scripts/)")
NONCODE = (".md", ".markdown", ".json", ".yaml", ".yml", ".txt", ".log", ".csv",
           ".toml", ".lock", ".ini", ".cfg", ".conf", ".xml", ".env")
def noncode(p):
    return p.lower().endswith(NONCODE)
# A source path can also reach the verb through an earlier command: `cd src/ &&
# grep -rn Foo .` or `D=src/; grep -rn Foo $D` (QA round 1 F-02). Track the cd
# directory and simple assignments; expand $NAME / ${NAME} before judging.
env, cd_src = {}, False
def expand(x):
    return re.sub(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", lambda m: env.get(m.group(1), m.group(0)), x)
def check(text):
    global cd_src
    lx = shlex.shlex(text.replace(chr(10), " ; "), posix=False, punctuation_chars=";&|")
    lx.whitespace_split = True
    seg = []
    for t in list(lx) + [";"]:
        if not set(t) <= set(";&|"):
            seg.append(t)
            continue
        # A "$(...)" argument is its own command: its verb pairs only with its own
        # paths. `git -C /r/apps/x commit -m "$(cat <<EOF ... EOF)"` leaves a bare
        # `cat` in there (QA round 2, R2-07); `echo "$(cat apps/x.ts)"` still blocks.
        # The literal rest of the word stays with the outer command, so
        # grep Foo "$(pwd)/src/" still blocks (QA round 3, F-01). A cd or an
        # assignment inside runs in a subshell and does not leak out (F-05).
        # The lexer splits "$(cat "src/x")" at the inner quote; rejoin the pieces
        # until the $( closes, so the substitution is still its own command
        # (QA round 4 F-02, round 5 F-01). Never closes -> left whole, outer.
        def shed(y):
            while re.search(r"\$\([^()]*\)", y):
                y = re.sub(r"\$\([^()]*\)", "", y)
            return y
        merged, i = [], 0
        while i < len(seg):
            x, j = seg[i], i + 1
            if x.startswith(chr(34)) and "$(" in shed(x):
                y, k = x, j
                while k < len(seg) and "$(" in shed(y):
                    y, k = y + " " + seg[k], k + 1
                if "$(" not in shed(y):
                    x, j = y, k
            merged.append(x)
            i = j
        seg = merged
        subs = [x for x in seg if x.startswith(chr(34)) and "$(" in x and "$(" not in shed(x)]
        outer = [shed(x) if x in subs else x for x in seg]
        seg = outer
        for x in subs:
            saved = (cd_src, dict(env))
            check(x[1:-1].replace("$(", " ; ").replace(")", " ; "))
            cd_src, env_back = saved
            env.clear(); env.update(env_back)
        bare = [expand(x.strip(chr(34) + chr(39) + "()")) for x in seg]
        while bare and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", bare[0]):
            k, v = bare.pop(0).split("=", 1)
            env[k] = v
        v = VERB.search(" ".join(seg))
        if bare[:1] == ["cd"]:
            cd_src = len(bare) > 1 and bool(SRC.search(bare[1].rstrip("/") + "/"))
        elif v:
            paths = [x for x in bare if SRC.search(x)]
            globs = [x.split("=", 1)[1] for x in bare if x.startswith(("--include=", "--glob="))]
            globs += [bare[i + 1] for i, x in enumerate(bare[:-1]) if x in ("--include", "-g", "--glob")]
            globs = [g for g in globs if not g.startswith("!")]   # rg -g "!x" excludes
            last = bare[-1] if len(bare) > 1 else ""
            if globs and all(map(noncode, globs)):
                pass
            elif paths and not all(map(noncode, paths)):
                sys.exit(0)
            elif (not paths and cd_src and last and not noncode(last)
                  and not last.startswith(("/", "~"))
                  and (v.group(2) in ("grep", "rg", "find") or re.search(r"\.[A-Za-z0-9]+$", last))):
                # Relative operand under a source dir we cd-ed into. Absolute paths
                # do not live there, and a reader needs a code file -- `cd src &&
                # tail -f /tmp/server.out`, `cd apps/web && cat Makefile` (R2-06).
                sys.exit(0)
        seg = []
check(os.environ["BNAV_SCAN"])
sys.exit(3)
' 2>/dev/null
    # Only an explicit 3 releases: a lexer error or a missing python3 exits with
    # something else and keeps the block.
    [ $? -ne 3 ]
  }
  # The path prefilter also admits a bare dir word (`cd src && …`), so the
  # per-command check sees the cd case; that check makes the real decision.
  if echo "$BNAV_SCAN" | grep -qE '(^|[[:space:]|;&(])(grep|rg|find|cat|head|tail|wc)([[:space:]]|$)' && echo "$BNAV_HEAD" | grep -qE '(src|app|apps|lib|pkg|internal|hooks|agents|scripts)(/|[[:space:]]|$)' \
     && _bnav_source_segment "$BNAV_SCAN"; then

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
      # There is no bypass marker. '# cmm-exempt' was one, scoped in this message
      # to non-code targets; agents learned it from the message and used it on
      # source anyway -- 114 uses in 12 maintainx sessions, 77 on source code
      # (2026-10-14). The non-code cases it served now pass on their own (the
      # per-command check above), and Read is never blocked, so a session
      # cannot wedge here. Same arc as ctx-payload-guard's '# ctx-truncate-ok'.
      cat >&2 <<EOF
BLOCKED: Use CMM tools instead of Bash navigation for code search.
$(_cmm_recovery_lines "$_TERM")$(_perl_note "$BASH_CMD")
See skill \`cmm-rules\` for the full protocol.
(Non-code files -- .json, .yaml, .md, .log, config -- are not gated: name the
file or restrict with --include='*.yaml'. To read a file, use Read.)
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
  # GNU FIRST, BSD second -- the order is load-bearing, not stylistic. On GNU
  # coreutils `-f` is --file-system, which SUCCEEDS for any existing file and
  # prints filesystem info, so `stat -f %m || stat -c %Y` never reaches the
  # fallback and the key becomes a per-platform constant. `-c` is unknown to BSD
  # stat, which exits non-zero, so trying it first degrades correctly on both.
  # This hook installs to ~/.claude and runs for every repo, so getting it
  # backwards restores the "first read is permanent" bug on all of Linux.
  _CFG_MTIME=$(stat -c %Y "$_CMM_CFG" 2>/dev/null || stat -f %m "$_CMM_CFG" 2>/dev/null || echo 0)
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
