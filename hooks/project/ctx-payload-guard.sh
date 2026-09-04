#!/bin/bash
# ctx-payload-guard.sh — PreToolUse hook: hard-block output truncation inside Context Mode payloads.
# BLOCKING: exits 2 when a shell payload pipes stdout into head/tail, or redirects stdout to a file.
# Both discard bytes before ctx_* can index them, so the output is never ctx_search-able later.
#
# Install: cp hooks/project/ctx-payload-guard.sh .claude/hooks/ && chmod +x .claude/hooks/ctx-payload-guard.sh
# Register in .claude/settings.json (plugin-form names FIRST, MCP-server-form second):
#   "hooks": { "PreToolUse": [{
#     "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute|mcp__plugin_context-mode_context-mode__ctx_execute_file|mcp__plugin_context-mode_context-mode__ctx_batch_execute|mcp__context-mode__ctx_execute|mcp__context-mode__ctx_execute_file|mcp__context-mode__ctx_batch_execute",
#     "hooks": [{"type": "command", "command": "bash .claude/hooks/ctx-payload-guard.sh"}] }] }
# Matcher: PreToolUse on all three ctx execution tools, both install-form prefixes.
#
# WHY A SEPARATE FILE FROM ctx-execute-cmm-nudge.sh (which also inspects ctx_execute):
#   That hook's parser fails OPEN on any pipe, heredoc or multi-line payload by design
#   (conservative single-statement classifier — see its F-06 lockstep note). This hook must fire
#   ON pipes. One file cannot hold both contracts without the parsers drifting, which is exactly
#   the divergence that F-06 note memorializes. Preconditions differ too: that gate only fires in
#   a CMM-indexed repo, whereas truncation is wrong regardless of CMM.
#
# WHY NO SHARED LIB: this hook makes no git calls and needs no repo root, CMM registration or
#   sentinel probe. A PreToolUse on mcp__…__ctx_execute firing at all is proof Context Mode is
#   live — a stronger signal than any sentinel. tests/test-hooks-use-shared-lib.sh only fails a
#   hook that inlines the git repo-root walk without sourcing project-root.sh; this hook runs no
#   git at all. (That test greps for the literal command string, comments included — so do not
#   quote it here.)
#
# STREAM RULE: only stdout leaving the pipeline defeats capture. `2> err.log`, `2>/dev/null`,
#   `2>&1` and `>&2` are normal hygiene and never block; `1> out.log` DOES block despite the fd
#   digit. Executable spec: scripts/analyze-antipatterns.py --selftest.

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Python source via quoted heredoc (same pattern as cmm-orient-nudge.sh) so the
# detector can use both quote characters freely. `read -r -d ''` returns non-zero
# at EOF, hence the `|| true`.
read -r -d '' _PY <<'PYEOF' || true
import json, re, sys

ACCEPTED = {
    "mcp__plugin_context-mode_context-mode__ctx_execute",
    "mcp__plugin_context-mode_context-mode__ctx_execute_file",
    "mcp__plugin_context-mode_context-mode__ctx_batch_execute",
    "mcp__context-mode__ctx_execute",
    "mcp__context-mode__ctx_execute_file",
    "mcp__context-mode__ctx_batch_execute",
}
# ">" is a comparison operator outside shell; scanning a JS or Python payload for
# redirects false-positives on ordinary code.
SHELLY = {"shell", "bash", "sh", "zsh", "", None}

EXEMPT = re.compile(r"#\s*ctx-truncate-ok\b")
PIPE_TRUNC = re.compile(r"(?<!\|)\|(?!\|)\s*(?:head|tail)\b[^|;&\n]*")
TEE = re.compile(r"\|\s*tee\b")
REDIR = re.compile(r"(?P<fd>\d)?(?P<op>&?>>?&?)\s*(?P<target>[^\s;|&()]+)")
# `(?<!<)<<(?!<)` so a here-STRING (`<<< word`) is not mistaken for a here-DOC.
# Without the guards this matched `<<< x`, took "x" as the terminator, and blanked
# every following line until one equalled "x" -- scrubbing away real truncations
# in the rest of a multi-line payload.
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*['\"]?(\w+)")
HEREDOC_LINE = re.compile(r"(?<!<)<<(?!<)")


def scrub(s):
    """Blank quoted spans, $( ), backticks and heredoc bodies with same-length
    placeholders so operator scanning never fires on text inside them. Whole-string,
    not line-based: a multi-line `git commit -m "..."` crosses newlines."""
    out = list(s)
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == "'" or c == '"':
            j = i + 1
            while j < n and s[j] != c:
                j += 1
            for k in range(i, min(j + 1, n)):
                out[k] = " "
            i = j + 1
        elif c == "`":
            j = i + 1
            while j < n and s[j] != "`":
                j += 1
            for k in range(i, min(j + 1, n)):
                out[k] = " "
            i = j + 1
        elif c == "$" and i + 1 < n and s[i + 1] == "(":
            depth, j = 1, i + 2
            while j < n and depth:
                if s[j] == "(":
                    depth += 1
                elif s[j] == ")":
                    depth -= 1
                j += 1
            for k in range(i, min(j, n)):
                out[k] = " "
            i = j
        else:
            i += 1
    scrubbed = "".join(out)
    raw_lines = s.split("\n")
    res, term = [], None
    for idx, line in enumerate(scrubbed.split("\n")):
        if term is not None:
            res.append(" " * len(line))
            if raw_lines[idx].strip() == term:
                term = None
            continue
        m = HEREDOC.search(raw_lines[idx])
        res.append(line)
        if m:
            term = m.group(1)
    return "\n".join(res)


# A redirect whose left-hand command only emits literal content is file
# AUTHORING, not output capture: `echo '{...}' > config.json` discards nothing,
# because nothing was going to be printed for the index. Same category as the
# heredoc case below. Found by dogfooding -- the guard blocked a test fixture
# being written, which is friction with no alternative to offer.
AUTHORING = re.compile(r"(?:^|[;&|]|\|\||&&|\n)\s*(?:echo|printf)\b[^;&|\n]*$")


def redirect_hit(scrubbed, raw):
    """Return (match, target) if stdout goes to a file, else None."""
    # Heredoc lines are file AUTHORING (`cat > script.sh <<EOF`), not output
    # truncation: nothing is discarded because nothing was going to print.
    heredoc = set(i for i, ln in enumerate(raw.split("\n")) if HEREDOC_LINE.search(ln))
    for m in REDIR.finditer(scrubbed):
        if scrubbed.count("\n", 0, m.start()) in heredoc:
            continue
        if AUTHORING.search(scrubbed[:m.start()]):
            continue
        fd, op, target = m.group("fd"), m.group("op"), m.group("target")
        if "&" in op and op not in ("&>", "&>>"):
            continue                                   # >&2 duplicates an fd
        if op in ("&>", "&>>"):
            fd = "1"                                   # &>file == >file 2>&1
        if fd is None:
            fd = "1"                                   # bare > is stdout
        if fd != "1":
            continue                                   # 2>err.log, 3>trace.log
        if target.startswith("&") or target.lstrip("&").isdigit():
            continue
        if target.startswith("/dev/"):
            continue                                   # discarding; nothing to recover
        if target in raw[m.end():]:
            continue                                   # file is read back later
        return m, target
    return None


def check(text, language):
    """-> (kind, token, target, suggested) | ("EXEMPT",...) | None."""
    if (language or "").lower() not in SHELLY:
        return None
    if EXEMPT.search(text):
        return ("EXEMPT", "", "", "")
    scrubbed = scrub(text)
    m = PIPE_TRUNC.search(scrubbed)
    if m:
        token = text[m.start():m.end()].strip()
        return ("pipe", token, "", (text[:m.start()] + text[m.end():]).strip())
    if not TEE.search(scrubbed):
        hit = redirect_hit(scrubbed, text)
        if hit:
            m, target = hit
            token = text[m.start():m.end()].strip()
            return ("redirect", token, target,
                    (text[:m.start()] + text[m.end():]).strip())
    return None


try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)                                        # malformed JSON -> fail open

tool = d.get("tool_name") or ""
if tool not in ACCEPTED:
    sys.exit(0)
ti = d.get("tool_input") or {}

payloads = []
if tool.endswith("ctx_batch_execute"):
    for i, c in enumerate(ti.get("commands") or []):
        if isinstance(c, dict) and isinstance(c.get("command"), str):
            payloads.append(("commands[%d]" % i, "shell", c["command"]))
else:
    code = ti.get("code")
    if isinstance(code, str):
        payloads.append(("code", ti.get("language"), code))

# Exempt is per payload ENTRY: a marked command in a batch is skipped, but the
# scan continues so it cannot whitelist its siblings. Only report EXEMPT (for the
# counter) if nothing else in the call blocked.
saw_exempt = False
for label, lang, text in payloads:
    r = check(text, lang)
    if r is None:
        continue
    kind, token, target, suggested = r
    if kind == "EXEMPT":
        saw_exempt = True
        continue
    # One field per line, and whitespace in the token collapsed. A tab-delimited
    # record broke when a multi-line payload put a newline inside the token: the
    # shell's `cut -f5` then read past the end of line 1 and rendered a message
    # with an empty tool name.
    token = " ".join(token.split())
    target = " ".join(target.split())
    sys.stdout.write("BLOCK\n%s\n%s\n%s\n%s\n%s\n" % (kind, label, token, tool, target))
    sys.stdout.write("---PAYLOAD---\n")
    sys.stdout.write(suggested)
    sys.exit(0)

if saw_exempt:
    print("EXEMPT")
PYEOF

RESULT=$(printf '%s' "$INPUT" | python3 -c "$_PY" 2>/dev/null)

# Parse failure, python3 absent, or nothing to say → allow
[ -z "$RESULT" ] && exit 0

VERDICT=$(printf '%s' "$RESULT" | sed -n '1p')

case "$VERDICT" in
  EXEMPT)
    bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "ctx_payload_exempt" 2>/dev/null || true
    exit 0
    ;;
  BLOCK) ;;
  *) exit 0 ;;
esac

KIND=$(printf   '%s' "$RESULT" | sed -n '2p')
LABEL=$(printf  '%s' "$RESULT" | sed -n '3p')
TOKEN=$(printf  '%s' "$RESULT" | sed -n '4p')
TOOL=$(printf   '%s' "$RESULT" | sed -n '5p')
TARGET=$(printf '%s' "$RESULT" | sed -n '6p')
SUGGESTED=$(printf '%s' "$RESULT" | sed -n '/^---PAYLOAD---$/,$p' | sed '1d')

# ctx_batch_execute has no intent=; its equivalent is the queries= array.
case "$TOOL" in
  *ctx_batch_execute)
    RECOVER="  ${TOOL}(commands=[{label: \"…\", command: \"${SUGGESTED}\"}], queries=[\"<what you are looking for>\"])"
    ASK="queries=" ;;
  *)
    RECOVER="  ${TOOL}(language=\"shell\", code=\"${SUGGESTED}\", intent=\"<what you are looking for>\")"
    ASK="intent=" ;;
esac

if [ "$KIND" = "pipe" ]; then
  cat >&2 <<EOF
[ctx-payload-guard] BLOCKED -- \`${TOKEN}\` discards output before Context Mode indexes it.
Offending payload: ${LABEL}

REPLACE WITH:
${RECOVER}

The pipe is dropped and ${ASK} added. Context Mode indexes the FULL output and returns only
the sections matching your question, so truncating first throws data away for no context
saving. Output over 5KB flips to FTS5 search-mode automatically.
Bypass: add '# ctx-truncate-ok' when the truncated slice IS the answer.
EOF
else
  cat >&2 <<EOF
[ctx-payload-guard] BLOCKED -- \`${TOKEN}\` sends stdout to a file, so nothing is captured.
Offending payload: ${LABEL}

REPLACE WITH:
${RECOVER}

Context Mode indexes stdout. Redirect it and stdout is empty: nothing is ctx_search-able
later and ${ASK} goes inert. If you genuinely need the file to persist, tee it so stdout
still flows:
  <command> 2>&1 | tee ${TARGET}
Redirecting stderr (2> file, 2>/dev/null, 2>&1) is fine and never blocked.
Bypass: add '# ctx-truncate-ok'.
EOF
fi

bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "ctx_payload" 2>/dev/null || true

exit 2
