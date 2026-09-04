#!/usr/bin/env python3
"""analyze-antipatterns.py — measure ctx/CMM anti-pattern prevalence in Claude Code transcripts.

Companion to scripts/analyze-enforcement.py. That one asks "does the hook fire?";
this one asks "how often does the model do the thing rules/ctx-rules.md forbids?"
— and, critically, WHERE: in plain Bash (which ctx-execute-enforcer.sh gates) vs
inside a ctx_execute / ctx_batch_execute payload (unpoliced as of 2026-09-03).

Usage:
    python3 scripts/analyze-antipatterns.py [days]      # default 30
    python3 scripts/analyze-antipatterns.py --selftest  # verify the detectors

Read-only. Walks ~/.config/claude-code/projects/**/*.jsonl.

STRONG vs WEAK
--------------
STRONG signals are unambiguous output suppression:
  * `cmd | head` / `cmd | tail`  — piping stdout into a truncator
  * stdout redirected to a file  — `cmd > out.log` (fd 1 only; see below)
WEAK signals are line-range extraction (`sed -n 'a,bp'`, `awk 'NR<=N'`, `grep -m N`).
They are often a legitimate computed excerpt, so they are reported separately
rather than summed. This split matters: once head/tail is gated, the cheapest
evasion is exactly the weak set, and a fall in STRONG with a rise in WEAK is
migration, not improvement.

Stream rule: only stdout leaving the pipeline defeats capture. `2> err.log`,
`2>/dev/null`, `2>&1` and `>&2` are normal hygiene and are NOT anti-patterns.
`1> out.log` IS one — a naive "digit before >" exclusion would wrongly pass it.

MEASUREMENT LIMIT
-----------------
A hook that exits 0 silently leaves no transcript trace, so the "caught by a hook"
column counts hooks that EMITTED. Absence of an emission is not proof a hook did
not run.
"""
import collections
import json
import os
import re
import sys
import time

ROOT = os.path.expanduser("~/.config/claude-code/projects")

# Shell payloads only. `>` is a comparison operator in JS and Python, which
# false-positived an earlier draft of this script.
SHELLY = {"shell", "bash", "sh", "zsh", "", None}

RE_PIPE_TRUNC = re.compile(r"(?<!\|)\|(?!\|)\s*(?:head|tail)\b")
RE_TEE = re.compile(r"\|\s*tee\b")
# `echo '{...}' > config.json` is file AUTHORING: nothing was going to be printed
# for the index, so nothing is discarded. Same category as a heredoc.
RE_AUTHORING = re.compile(r"(?:^|[;&|]|\|\||&&|\n)\s*(?:echo|printf)\b[^;&|\n]*$")
# A redirect token, capturing any fd digit immediately before it and the target.
RE_REDIR = re.compile(r"(?P<fd>\d)?(?P<op>&?>>?&?)\s*(?P<target>[^\s;|&()]+)")

# `(?<!<)<<(?!<)` so a here-STRING (`<<< word`) is not mistaken for a here-DOC.
# Without the guards this matched `<<< x`, took "x" as the terminator, and blanked
# every following line until one equalled "x".
RE_HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*['\"]?(\w+)")
RE_HEREDOC_LINE = re.compile(r"(?<!<)<<(?!<)")

RE_SED_RANGE = re.compile(r"sed\s+-n\s+['\"]?\s*\d+\s*,\s*\d+\s*p")
RE_AWK_NR = re.compile(r"awk\s+['\"][^'\"]*NR\s*[<>=]")
RE_GREP_M = re.compile(r"\bgrep\b[^|;&\n]*\s-m\s*\d+")

FAILLIT = r"['\"]?(?:not ok|FAILED|FAILURE|\bFAIL\b|Traceback|panic:|Segmentation fault)"
RE_ASSERT = re.compile(r"\bgrep\b[^|;&\n]*" + FAILLIT)

# Bash-only / zsh-divergent constructs. ctx_execute runs $SHELL (zsh on macOS
# defaults), not bash -- see context-mode src/runtime.ts detectRuntimes().
BASHISMS = [
    ("${!var} indirect", re.compile(r"\$\{!\w")),
    ("${var^^}/${var,,}", re.compile(r"\$\{\w+(?:\^\^|,,)")),
    ("mapfile/readarray", re.compile(r"\b(?:mapfile|readarray)\b")),
    ("read -a", re.compile(r"\bread\s+(?:-\w*\s+)*-a\b")),
    ("declare/local -n", re.compile(r"\b(?:declare|local)\s+-n\b")),
    ("unquoted word-split for", re.compile(r"\bfor\s+\w+\s+in\s+\$\w+\s*[;\n]")),
]


def strip_quoted(s):
    """Blank out quoted spans, $( ) and backtick spans, and heredoc bodies, so
    operator scanning never fires on text inside them. Same-length placeholders
    keep offsets stable. Whole-string, not line-based: a multi-line
    `git commit -m "..."` crosses newlines."""
    out = list(s)
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c in "'\"":
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
    # Heredoc bodies: from the << line through the terminator line.
    lines = scrubbed.split("\n")
    raw_lines = s.split("\n")
    result, skip_until = [], None
    for idx, line in enumerate(lines):
        if skip_until is not None:
            result.append(" " * len(line))
            if raw_lines[idx].strip() == skip_until:
                skip_until = None
            continue
        m = RE_HEREDOC.search(raw_lines[idx])
        result.append(line)
        if m:
            skip_until = m.group(1)
    return "\n".join(result)


def redirect_hit(scrubbed, raw):
    """Return the offending target if stdout is redirected to a file, else None."""
    # Heredoc lines are file *authoring* (`cat > script.sh <<'EOF'`), not output
    # truncation: nothing is being discarded because nothing was going to print.
    heredoc_lines = {i for i, ln in enumerate(raw.split("\n")) if RE_HEREDOC_LINE.search(ln)}
    for m in RE_REDIR.finditer(scrubbed):
        if scrubbed.count("\n", 0, m.start()) in heredoc_lines:
            continue
        if RE_AUTHORING.search(scrubbed[:m.start()]):
            continue                      # echo/printf > file is authoring
        fd, op, target = m.group("fd"), m.group("op"), m.group("target")
        if "&" in op and op != "&>" and op != "&>>":
            continue                      # >&2, >&1 — duplicating, not a file
        if op in ("&>", "&>>"):
            fd = "1"                      # &> is shorthand for >file 2>&1
        if fd is None:
            fd = "1"                      # bare > is stdout
        if fd != "1":
            continue                      # 2> err.log, 3> trace.log — stream splitting
        if target.startswith("&") or target.lstrip("&").isdigit():
            continue                      # > &2
        if target.startswith("/dev/"):
            continue                      # discarding, nothing to recover
        # The file is genuinely needed if something later reads it back.
        after = raw[m.end():]
        if target in after:
            continue
        return target
    return None


def classify(text, language=None):
    """-> dict with 'strong', 'weak', 'assert', 'bashism' finding lists."""
    if (language or "").lower() not in SHELLY:
        return {"strong": [], "weak": [], "assert": [], "bashism": []}
    scrubbed = strip_quoted(text)
    strong = []
    if RE_PIPE_TRUNC.search(scrubbed):
        strong.append("pipe-to-head/tail")
    if not RE_TEE.search(scrubbed):
        t = redirect_hit(scrubbed, text)
        if t:
            strong.append("stdout-to-file")
    # Weak / assert / bashism detectors run on the RAW text, not the scrubbed copy.
    # Scrubbing exists to stop STRONG operators firing on text inside quotes
    # (`echo "a | head"`). But these patterns live in a command's own quoted
    # ARGUMENTS -- `sed -n '1,3p'`, `grep -m1 'not ok'`, `"${!var}"` -- so
    # scrubbing them blanks the very thing being detected. (Measured: scrubbing
    # first collapsed sed-line-range in ctx_execute from ~3,135 to 0.)
    weak = []
    for label, rx in (("sed line-range", RE_SED_RANGE), ("awk NR-range", RE_AWK_NR),
                      ("grep -m N", RE_GREP_M)):
        if rx.search(text):
            weak.append(label)
    asserts = ["grep for guessed failure literal"] if RE_ASSERT.search(text) else []
    bashisms = [label for label, rx in BASHISMS if rx.search(text)]
    return {"strong": strong, "weak": weak, "assert": asserts, "bashism": bashisms}


# --------------------------------------------------------------------- selftest
SELFTEST = [
    # (payload, language, expect_strong)  -- doubles as the spec for the
    # ctx-payload-guard hook: every False row MUST NOT be blocked.
    ("orb list 2>&1 | head -20", "shell", True),
    ("cmd | tail -50", "shell", True),
    ("cmd | head -c 2000", "shell", True),
    ("find . | sort | uniq -c | sort -rn | head -20", "shell", True),
    ("cmd > out.log", "shell", True),
    ("cmd 1> out.log", "shell", True),
    ("cmd >> run.txt", "shell", True),
    ("cmd > out.log 2>&1", "shell", True),
    ("cmd &> everything.log", "shell", True),
    # --- must NOT fire ---
    ("cmd 2>&1 | tee run.log", "shell", False),
    ("cmd | tee /tmp/x", "shell", False),
    ("head -50 CHANGELOG.md", "shell", False),
    ("tail -f app.log", "shell", False),
    ("cmd 2> err.log", "shell", False),
    ("cmd 2>/dev/null", "shell", False),
    ("cmd 2>&1", "shell", False),
    ("cmd 3> trace.log", "shell", False),
    ("echo hi >&2", "shell", False),
    ("cmd > /dev/null", "shell", False),
    ("cmd > out.log && grep foo out.log", "shell", False),
    ("V=$(git rev-list --count HEAD | head -1)", "shell", False),
    ("echo \"a | head\"", "shell", False),
    ("grep 'x > y' file", "shell", False),
    ("a || b", "shell", False),
    ("cat > script.sh <<'EOF'\ncmd | head -5\nEOF", "shell", False),
    # A here-STRING is not a here-DOC: `<<< x` must not start a scrub that swallows
    # the rest of the payload, or later truncations go undetected.
    ("read -ra a <<< x\ncmd | head -5", "shell", True),
    ("cmd <<< x > out.log", "shell", True),
    # echo/printf into a file is authoring, not output capture.
    ("echo hi > /tmp/out.log", "shell", False),
    ('printf "%s" x > /tmp/out.json', "shell", False),
    ("grep -rn foo src/ > /tmp/hits.log", "shell", True),
    ("const a = b > c ? 1 : 2", "javascript", False),
    ("x = y >> 1", "python", False),
    ("print $fh > 5", "perl", False),
]


def selftest():
    failed = 0
    for payload, lang, expect in SELFTEST:
        got = bool(classify(payload, lang)["strong"])
        if got != expect:
            failed += 1
            print(f"FAIL  expected strong={expect} got={got}: {payload!r} [{lang}]")
        else:
            print(f"ok    strong={got:<5} {payload!r} [{lang}]")
    # bashism detector
    for payload, expect in (("v=x; echo ${!v}", True), ("echo ${v}", False),
                            ("for f in $files; do echo $f; done", True)):
        got = bool(classify(payload, "shell")["bashism"])
        if got != expect:
            failed += 1
            print(f"FAIL  expected bashism={expect} got={got}: {payload!r}")
        else:
            print(f"ok    bashism={got:<5} {payload!r}")
    print(f"\nselftest: {failed} failure(s)")
    return 1 if failed else 0


# ------------------------------------------------------------------- transcript
CTX_SUFFIXES = ("ctx_execute", "ctx_execute_file", "ctx_batch_execute")


def payloads(name, inp):
    """-> [(surface, language, text)] for the shell text this tool call carries."""
    if name == "Bash":
        c = inp.get("command")
        return [("Bash", "shell", c)] if isinstance(c, str) else []
    if name.endswith("ctx_batch_execute"):
        return [("ctx_batch_execute", "shell", c["command"])
                for c in (inp.get("commands") or [])
                if isinstance(c, dict) and isinstance(c.get("command"), str)]
    for suffix in ("ctx_execute_file", "ctx_execute"):
        if name.endswith(suffix):
            c = inp.get("code")
            return [(suffix, inp.get("language"), c)] if isinstance(c, str) else []
    return []


def flatten(c):
    if isinstance(c, str):
        return c
    out = []
    if isinstance(c, list):
        for b in c:
            if isinstance(b, str):
                out.append(b)
            elif isinstance(b, dict):
                if isinstance(b.get("text"), str):
                    out.append(b["text"])
                cc = b.get("content")
                if isinstance(cc, str):
                    out.append(cc)
                elif isinstance(cc, list):
                    out.append(flatten(cc))
    return "\n".join(out)


def main(days):
    cutoff = time.time() - days * 86400
    files = []
    for dirpath, _d, fnames in os.walk(ROOT):
        for fn in fnames:
            if not fn.endswith(".jsonl"):
                continue
            p = os.path.join(dirpath, fn)
            try:
                if os.path.getmtime(p) >= cutoff:
                    files.append(p)
            except OSError:
                pass

    calls = collections.Counter()
    strong = collections.Counter()
    weak = collections.Counter()
    asserts = collections.Counter()
    bashism = collections.Counter()
    blocked = collections.Counter()
    detail = collections.defaultdict(collections.Counter)
    intent_x = collections.Counter()
    langs = collections.Counter()

    print(f"corpus: {len(files)} transcripts touched in last {days}d\n")

    for path in files:
        dirty = {}
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("type") == "assistant":
                    for b in (r.get("message") or {}).get("content") or []:
                        if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                            continue
                        name, inp = b.get("name", ""), (b.get("input") or {})
                        for surf, lang, text in payloads(name, inp):
                            if surf.startswith("ctx"):
                                langs[(lang or "(none)")] += 1
                            if (lang or "").lower() not in SHELLY:
                                continue
                            calls[surf] += 1
                            f = classify(text, lang)
                            for k in f["strong"]:
                                detail[surf][k] += 1
                            for k in f["weak"]:
                                detail[surf]["~" + k] += 1
                            for k in f["assert"]:
                                detail[surf]["!" + k] += 1
                            for k in f["bashism"]:
                                detail[surf]["z:" + k] += 1
                            if f["strong"]:
                                strong[surf] += 1
                                dirty[b.get("id")] = surf
                            if f["weak"]:
                                weak[surf] += 1
                            if f["assert"]:
                                asserts[surf] += 1
                            if f["bashism"]:
                                bashism[surf] += 1
                            if surf == "ctx_execute":
                                intent_x[(bool(inp.get("intent")), bool(f["strong"]))] += 1
                elif r.get("type") == "user":
                    for b in (r.get("message") or {}).get("content") or []:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            tid = b.get("tool_use_id")
                            if tid in dirty and "hook error:" in flatten(b.get("content")):
                                blocked[dirty[tid]] += 1

    def pct(a, b):
        return f"{100.0*a/b:.1f}%" if b else "n/a"

    order = ("Bash", "ctx_execute", "ctx_execute_file", "ctx_batch_execute")
    print("=" * 78)
    print("1. STRONG anti-patterns (pipe-to-head/tail, stdout-to-file)")
    print("=" * 78)
    print(f"{'surface':20} {'shell calls':>12} {'strong':>8} {'rate':>8} {'caught by a hook':>18}")
    for s in order:
        if calls[s]:
            print(f"{s:20} {calls[s]:12d} {strong[s]:8d} {pct(strong[s],calls[s]):>8} "
                  f"{blocked[s]:7d} ({pct(blocked[s], max(strong[s],1))})")

    print()
    print("=" * 78)
    print("2. WEAK signals — watch for migration once STRONG is gated")
    print("=" * 78)
    print(f"{'surface':20} {'weak':>8} {'rate':>8}   (~ = ambiguous: often a legitimate excerpt)")
    for s in order:
        if calls[s]:
            print(f"{s:20} {weak[s]:8d} {pct(weak[s],calls[s]):>8}")

    print()
    print("=" * 78)
    print("3. BREAKDOWN   (~ weak, ! assert-on-guessed-literal, z: bash-only syntax)")
    print("=" * 78)
    keys = sorted({k for s in detail for k in detail[s]})
    print(f"{'pattern':34}" + "".join(f"{s[:16]:>18}" for s in order))
    for k in keys:
        print(f"{k:34}" + "".join(f"{detail[s][k]:18d}" for s in order))

    print()
    print("=" * 78)
    print("4. intent= vs truncation on ctx_execute")
    print("=" * 78)
    tot = sum(intent_x.values())
    with_i = sum(n for (i, _), n in intent_x.items() if i)
    tr_i = sum(n for (i, s), n in intent_x.items() if i and s)
    tr_n = sum(n for (i, s), n in intent_x.items() if not i and s)
    print(f"   intent= present on {with_i}/{tot} = {pct(with_i, tot)} of shell ctx_execute calls")
    print(f"   truncation rate WITH intent=: {pct(tr_i, max(with_i,1))} | "
          f"WITHOUT: {pct(tr_n, max(tot-with_i,1))}")
    print("   (equal rates mean intent= is NOT displacing truncation)")

    print()
    print("=" * 78)
    print("5. language= on ctx_* calls  (shell payloads run $SHELL, not bash)")
    print("=" * 78)
    for k, v in langs.most_common(8):
        print(f"   {k:14} {v}")

    print()
    print("NOTE: 'caught by a hook' counts hooks that EMITTED. A hook that exits 0")
    print("      silently leaves no transcript trace, so absence is not proof.")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(main(int(sys.argv[1]) if len(sys.argv) > 1 else 30))
