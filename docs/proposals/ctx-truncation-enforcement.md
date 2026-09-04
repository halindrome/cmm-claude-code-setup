# Proposal: make the output-truncation rule self-teaching

**Status:** draft / not implemented
**Author:** field report from a Claude Opus 5 session in `corvex-build`, 2026-08-25
**Touches:** `rules/ctx-rules.md`, `skills/ctx-rules/SKILL.md`, `hooks/project/ctx-execute-enforcer.sh`, `rules/project-settings-example.json`

---

## 1. What happened

A single long session (four MR QA cycles plus a hardware install) violated the
Anti-patterns section of `ctx-rules.md` **dozens of times** while otherwise following the
stack closely — the agent used `ctx_execute` for essentially every shell call, used CMM
where applicable, and respected every hook block it hit.

The violations, by shape:

| Shape | Example from the session | Count |
|---|---|---|
| `cmd \| tail -N` | `bash /tmp/baseline.sh 2>&1 \| tail -60` | several |
| `cmd \| head -N` | `sh "$B" --dry-run 2>&1 \| head -40` | many |
| `cmd \| grep <pattern>` | `bash test_alloy_strip.sh 2>&1 \| grep -E '^(PASS\|FAIL\|ALL\|SOME)'` | every test run |
| `cmd > file` then analyse the file | `ssh … --dry-run > /tmp/drybench.log 2>&1` | 5+ |
| `2>/dev/null` on a diagnostic | `docker ps --format … 2>/dev/null \| wc -l` | several |

Two of these caused **material errors**, not just lost bytes:

1. `docker ps … 2>/dev/null | wc -l` turned a docker-socket *permission denial* into an
   apparent "zero containers running", which sent the agent investigating a non-existent
   outage on a freshly-installed gateway. The containers were fine.
2. The same swallow-stderr shape in a baseline capture made
   `docker exec rest-api findmnt /tmp/metrics` report "NOT a mountpoint" when the real
   answer was "permission denied". A **pre-install baseline reading was wrong**, and the
   agent only noticed because a later `sudo` run disagreed with it.

The user caught it and asked directly: *"tell me you didn't just run that whole thing
without using context mode… You didn't use the anti-pattern of tail or head or grep,
right?"* The answer was: it used `ctx_execute` throughout, and truncated inside the payload
almost every time.

---

## 2. What the rules already say (no strawman)

This proposal is **not** "the docs don't mention it". They do, in two bullets:

**Bullet 1 — truncation:**

> Never use output-truncation primitives (`head -N`, `tail -N`, `sed -n '1,Np'`,
> `grep -m N`, `awk 'NR<=N'`) to cap large command output in captured shell commands.
> … bytes discarded before capture are permanently lost and unsearchable. … It is
> advisory — no PreToolUse hook enforces it on sandbox payloads; compliance depends on the
> agent following the guideline.

**Bullet 2 — asserted patterns:**

> Never assert in advance which literal string signals failure in output whose format you
> do not control. `grep -c 'not ok' run.log` returning `0` means *your pattern did not
> match* — it does not mean *nothing failed*. … you cannot fix this by keeping the bytes
> out of your window by redirecting to a file, because that solves cost, not correctness.
> So `intent=` is not merely a size threshold; it is the difference between asserting a
> pattern and asking a question.

Bullet 2 is a genuinely good rule and it covers the `| grep -E 'PASS|FAIL'` case squarely.
The gap is not coverage. It is **retrievability at the moment of composition** and
**enforcement**.

---

## 3. Why compliance failed anyway

Five specific, fixable reasons. Each is a claim about how the text reads under load, not a
claim that it is wrong.

### 3.1 The forbidden list is a list of primitives, and it invites pattern-matching

Every named primitive is a *count* limiter: `head -N`, `tail -N`, `sed -n '1,Np'`,
`grep -m N`, `awk 'NR<=N'`. The session's single most frequent violation was a *content*
filter — `| grep -E '^(PASS|FAIL|ALL|SOME)'` — which discards far more than `head -20`
would. It matches no listed primitive. `grep -m N` appearing on the list actively implies
plain `grep` was considered and excluded.

The rule that does cover it lives in a **different bullet**, framed as a correctness
problem rather than a truncation problem, so it is not retrieved when the agent is thinking
"am I about to truncate?"

### 3.2 "Indexing happens either way" outcompetes "bytes discarded before capture are lost"

Both sentences are present. The first is prominent, stated twice, and reassuring. The
second is a subordinate clause. The resulting belief is: *my output is indexed regardless,
so trimming is just context hygiene* — truncation reframed as a **virtue**. The
load-bearing word is "captured", and it is easy to read past.

### 3.3 "It is advisory — no PreToolUse hook enforces it" reads as permission

In this stack, hooks block hard and immediately. The same session was blocked twice within
minutes (compound Bash command; `Read` on a code file) and complied instantly both times,
because the block was unambiguous and arrived at the decision point. A rule that
*announces* it is unenforced is the rule that gets dropped when the session gets long.

The sentence is also **not technically true as a limitation** — see §5.

### 3.4 The redirect trap is described as a correctness gap, not an indexing gap

Bullet 2 says redirecting to a file "solves cost, not correctness". True — but it does not
say the thing that actually bit this session: **redirecting the payload's stdout to a file
means `ctx_execute` captures nothing at all.** The agent invented
`ssh … > /tmp/log` + `grep /tmp/log` as a *good-citizen* alternative to `| head`, believing
it was preserving the bytes. It preserved them on disk and removed them from the index —
strictly worse than the truncation it replaced.

A good-faith reading of the current text produces this move.

### 3.5 The rule is not where the decision is made

`ctx-rules.md` loads at session start. The decision happens hundreds of turns later while
composing a shell payload. The one piece of text the agent re-reads at that exact moment is
the **`ctx_execute` tool description**, which covers Think-in-Code thoroughly and says
nothing about not truncating.

---

## 4. Proposed rewrite — `rules/ctx-rules.md` Anti-patterns section

Replace the current Anti-patterns bullets with the following. Changes: positive pattern
first; ban defined by *effect* rather than by primitive list; the advisory sentence removed;
the redirect trap named as an indexing failure; a worked example.

````markdown
### Anti-patterns

**The pattern. Learn this shape, not the exception list:**

```
ctx_execute(
  language="shell",
  intent="what you actually want to know",
  code="<the command, unfiltered, printing everything>"
)
```

Then `ctx_search(queries=[...], source="execute:shell")` for the specifics. Output over
~5 KB comes back as section titles plus hits; the full text is indexed and retrievable.
Under 5 KB it returns inline. Either way nothing is lost.

- **Never drop bytes before they reach the payload's stdout.** The rule is about the
  *effect*, not a list of commands. All of these break it:
  - `cmd | head -N`, `cmd | tail -N`, `cmd | sed -n '1,Np'`, `cmd | awk 'NR<=N'` — count limiting
  - `cmd | grep <pattern>`, `cmd | grep -m N`, `cmd | rg <pattern>` — content filtering, which
    usually discards **more** than a `head -N` would
  - `cmd > file` / `cmd | tee file >/dev/null` — this is the worst one, because it looks
    responsible. It writes the bytes to disk and leaves the payload's stdout **empty**, so
    context mode indexes **nothing**. You have paid the full cost of running the command
    and kept none of the benefit.
  - `2>/dev/null`, `2>&1 >/dev/null` on anything diagnostic — a permission denial, a missing
    binary and a genuine empty result become indistinguishable. This has produced wrong
    conclusions in the field, not merely lost bytes: a swallowed docker-socket permission
    error read as "zero containers running" on a healthy host.

  Exception, unchanged: bare `head file` / `tail file` to read a small file is fine. It is
  the *pipe-to-truncate* shape that is banned.

- **Filter in code, after capture — never in the pipeline.** If you want a count, a diff or
  a subset, print the full output *and* the derived answer, or run the analysis in a
  `ctx_execute` payload that reads the indexed text. `intent=` exists so the filtering
  happens on the retrieval side, where a wrong guess is recoverable.

- **Never assert in advance which literal string signals failure in output whose format you
  do not control.** `grep -c 'not ok' run.log` returning `0` means *your pattern did not
  match* — it does not mean *nothing failed*. A harness reporting `Dubious, test returned
  255`, or a linter that reworded its summary between versions, both score clean, and clean
  is indistinguishable from a genuine pass. Index the output and **ask the question**.
  `intent=` is not merely a size threshold; it is the difference between asserting a pattern
  and asking a question.

**Worked example — a test run.** Wrong, and it is the most common violation:

```
bash tests/run-all.sh 2>&1 | grep -E '^(PASS|FAIL)'      # asserts the format; loses everything else
bash tests/run-all.sh > /tmp/t.log 2>&1                   # indexes NOTHING
```

Right:

```
ctx_execute(intent="which assertions failed and why", code="bash tests/run-all.sh 2>&1")
```

A crash, a stack trace, a harness that renamed its status strings, and a timeout all remain
findable. Under the wrong versions, each is silently a pass.
````

**Also delete** from the Context Mode overview paragraph the standalone reassurance
*"Indexing happens either way."* Replace with:

> Indexing happens either way — **for whatever reaches the payload's stdout.** Bytes you
> filter, truncate or redirect before that point are never captured and are unrecoverable.

Mirror all of the above into `skills/ctx-rules/SKILL.md`, which currently carries the same
text.

---

## 5. Proposed enforcement — the hook gap is configuration, not platform

`ctx-execute-enforcer.sh` is registered with `"matcher": "Bash"` only, so it never sees
`ctx_execute` payloads. But `settings.json` already carries a working matcher for
context-mode MCP tools:

```json
{
  "matcher": "mcp__plugin_context-mode_context-mode__*|mcp__context-mode__*",
  "hooks": [{ "type": "command", "command": "bash …/track-ctx-calls.sh" }]
}
```

So a `PreToolUse` hook **can** inspect `tool_input.code`. The claim in the rules that no
hook enforces this on sandbox payloads describes the current wiring, not a limitation — and
stating it in the rules file is what tells the agent the rule is optional.

### 5.1 New hook — `hooks/project/ctx-payload-guard.sh` (draft)

Deliberately **narrow and advisory-by-default**: it warns rather than blocks on first
offence, and only hard-blocks the redirect shape, which has no legitimate use inside a
payload whose entire purpose is to produce indexable stdout.

```bash
#!/usr/bin/env bash
# PreToolUse: mcp__*context-mode*__ctx_execute / ctx_execute_file / ctx_batch_execute
#
# Catches output-discarding shapes inside sandbox payloads, which ctx-execute-enforcer.sh
# cannot see because it is registered on the Bash matcher only.
#
# Philosophy: the payload's stdout IS the capture. Anything that empties or filters it
# before it is emitted defeats the tool being called.
set -uo pipefail

INPUT=$(cat)
CODE=$(printf '%s' "$INPUT" | jq -r '.tool_input.code // .tool_input.commands[]?.command // empty' 2>/dev/null)
[ -n "$CODE" ] || exit 0

# Strip quoted strings and comments before matching, so a grep INSIDE a heredoc that the
# payload writes to a remote file is not mistaken for a pipeline filter. Imperfect by
# design: false negatives are preferable to blocking legitimate work.
SCAN=$(printf '%s' "$CODE" | sed -e "s/#.*$//" )

_warn() { printf '%s\n' "$1" >&2; }

# --- HARD BLOCK: redirecting the payload's own stdout to a file ---
# This is the shape that indexes nothing while looking responsible.
if printf '%s' "$SCAN" | grep -qE '(^|[^2>])>[[:space:]]*/(tmp|var/tmp)/[A-Za-z0-9._-]+(\.log|\.txt|\.out)?[[:space:]]*(2>&1)?[[:space:]]*$'; then
  cat >&2 <<'MSG'
BLOCKED: this payload redirects its stdout to a file.

ctx_execute indexes the payload's STDOUT. Redirecting it to a file leaves stdout empty, so
context mode captures NOTHING — you pay the full cost of running the command and keep none
of the benefit. This is worse than truncating, not better.

Instead:
  ctx_execute(intent="<what you want to know>", code="<command, unredirected>")
then ctx_search(queries=[...], source="execute:shell").

If you genuinely need the file to exist on a REMOTE host, write it there inside the remote
shell (ssh host 'cmd > /remote/path') so the local payload's stdout still carries the text.
MSG
  exit 2
fi

# --- WARN: pipe-to-truncate and pipe-to-filter ---
HITS=""
printf '%s' "$SCAN" | grep -qE '\|[[:space:]]*(head|tail)[[:space:]]+-' && HITS="${HITS}  - | head/tail -N  (count truncation)\n"
printf '%s' "$SCAN" | grep -qE '\|[[:space:]]*(grep|rg)[[:space:]]' && HITS="${HITS}  - | grep/rg <pattern>  (content filter — usually discards more than head -N)\n"
printf '%s' "$SCAN" | grep -qE '\|[[:space:]]*sed[[:space:]]+-n' && HITS="${HITS}  - | sed -n  (range truncation)\n"
printf '%s' "$SCAN" | grep -qE '2>[[:space:]]*/dev/null' && HITS="${HITS}  - 2>/dev/null  (a permission error becomes indistinguishable from an empty result)\n"

if [ -n "$HITS" ]; then
  printf 'ADVISORY: this payload discards output before context mode can capture it:\n' >&2
  printf "$HITS" >&2
  cat >&2 <<'MSG'

Prefer: print everything, pass intent=, and query afterwards with ctx_search.
Filter in code AFTER capture, not in the pipeline — a wrong pattern is then recoverable.

Proceeding anyway (advisory).
MSG
  bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "ctx-payload-advisory" 2>/dev/null || true
fi

exit 0
```

### 5.2 Registration — `rules/project-settings-example.json`

```json
{
  "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute|mcp__plugin_context-mode_context-mode__ctx_execute_file|mcp__plugin_context-mode_context-mode__ctx_batch_execute|mcp__context-mode__ctx_execute|mcp__context-mode__ctx_execute_file|mcp__context-mode__ctx_batch_execute",
  "hooks": [
    {
      "type": "command",
      "command": "bash <ABS>/.claude/hooks/ctx-payload-guard.sh",
      "_comment": "Advisory on pipe-to-truncate/filter inside ctx_execute payloads; hard-blocks stdout>file, which indexes nothing"
    }
  ]
}
```

### 5.3 Why advisory-first

The compound-command block in `ctx-execute-enforcer.sh` taught this session's agent in
exactly one attempt. That is the model to copy. But a payload guard that hard-blocks
`| grep` would break legitimate work — a payload that greps a file it is analysing, or
builds a pipeline whose *result* it prints, is fine. Warning on those and blocking only the
redirect shape keeps the false-positive rate near zero while still landing the lesson at the
decision point.

Recommend shipping advisory-only for one release, reading
`scripts/analyze-gate-blocks.py` output for the `ctx-payload-advisory` counter, and
promoting to a block only if the advisory alone does not move the number.

---

## 6. The decision-point fix belongs upstream — and NOT in the tool description

The text an agent re-reads at the moment of composing a payload is the tool description.
The obvious move is to add *"Print everything — do not pipe through head/tail/grep"* there.

**That move is wrong, and checking upstream is what showed it.** `context-mode`'s
ADR-0002 (`docs/adr/0002-tool-description-style.md`, present at upstream tip `a0d0322`,
v1.0.169) forbids the tokens `NEVER`, `MANDATORY`, `FORBIDDEN`, `BLOCKED` and the phrase
`Never use`, mandates a `WHEN → WHEN NOT → RETURNS → EXAMPLE` structure, and enforces both
with a contract test in `tests/core/server.test.ts`. The proposed wording would have failed
that test. The ADR also states directly that voice-of-trainer text belongs in
`hooks/routing-block.mjs` and `CLAUDE.md`, *not* in tool descriptions — and it is right.

Two upstream asks survive, both verified as genuine gaps at upstream tip:

1. **A runtime "nothing was indexed" signal** when a payload's stdout is empty. This is the
   substantive one: it is a RETURNS-level fact rather than exhortation, and it reaches every
   caller with no install step — unlike a hook, which only protects repos where `setup.sh` has
   been run and stays current (a 2026-09-03 drift check found 5 of 15 active sibling repos on
   hook copies 2–5 months old).
2. **One paragraph in `hooks/routing-block.mjs`**, the layer ADR-0002 designates for this
   voice. Confirmed: it currently contains no guidance on truncation, filtering or
   redirection.

Drafted in full at `docs/proposals/upstream-context-mode-issue.md`.

**Consequence for §5 of this proposal:** the hook stays worth shipping, and its reach is better
than this document originally claimed — it fires at the decision point on the main thread **and**
inside subagents and Workflow workers. Its limit is deployment, not visibility: it protects only
repos where `setup.sh` has been run recently. The two proposals are complementary, not
alternatives.

**Superseded by measurement (2026-09-03):** §5.1 proposed *advisory* treatment for
pipe-to-truncate and blocking only for `stdout > file`. The advisory choice does not survive the
data — `ctx_execute` carries a truncation or redirect in **34.1%** of its 21,297 shell payloads and
**0.0%** are caught today, while advisory `SubagentStart` injection lands ~2,210 times per 30 days
and still leaves 52% zero-CMM sessions. Ship both forms as blocking, with a `# ctx-truncate-ok`
escape hatch. See `docs/proposals/enforcement-reach-vs-adoption-measurement.md`.

---

## 7. Test plan

Matching existing `tests/test-*.sh` conventions:

- `tests/test-ctx-payload-guard.sh`
  - blocks `code` containing `ssh host 'cmd' > /tmp/x.log 2>&1`
  - does **not** block `ssh host 'cmd > /remote/path'` (redirect inside the remote quote)
  - warns on `| head -40`, `| tail -60`, `| grep -E '^(PASS|FAIL)'`, `| sed -n '1,20p'`, `2>/dev/null`
  - stays silent on a clean payload
  - exits 0 (no-op) when `.tool_input.code` is absent or `jq` is unavailable
  - handles `ctx_batch_execute`'s `commands[].command` array shape
- `tests/test-rules-antipattern-wording.sh` — asserts `rules/ctx-rules.md` and
  `skills/ctx-rules/SKILL.md` stay in sync, and that the string `It is advisory` no longer
  appears in either.

---

## 8. Summary of the argument

The rules are not wrong and they are not missing the cases. They fail at three specific
joints:

1. the ban is expressed as a **primitive list**, so a content filter reads as permitted;
2. the reassurance **"indexing happens either way"** outranks the caveat that makes it
   conditional, turning truncation into apparent good hygiene;
3. the rule **announces that nothing enforces it**, in a stack where every other rule blocks
   — and the enforcement it disclaims is available today with a matcher that already exists.

Fixing 1 and 2 is a wording change. Fixing 3 is roughly one hook file.
