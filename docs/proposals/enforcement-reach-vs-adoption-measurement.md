# Measurement — does the enforcement stack reach the stream, and is it used?

**Date:** 2026-09-03
**Corpus:** `~/.config/claude-code/projects/**/*.jsonl` — every Claude Code transcript on this
machine. Primary window **30 days** (1,796 transcripts: 202 main-thread, 1,593 subagent).
Secondary window **120 days** (4,609 transcripts) used only because **no Workflow-spawned worker
ran in the last 30 days** — the most recent one is ~46 days old.
**Scripts:** `scripts/analyze-enforcement.py` and `scripts/analyze-antipatterns.py` (argument =
window in days). Both run together via `make measure` (`make measure DAYS=120`).

**Method.** Hook emissions are classified by **content fingerprint** — the literal strings emitted
by `hooks/{global,project}/*.sh` in this repo — never by `hookName`. Other hook suites (cmux,
codeisland, context-mode-soak) are installed on the same machine and would otherwise be miscounted;
they land in an `<other-hook-suite>` bucket. Hard blocks are read from `tool_result` bodies
containing `PreToolUse:… hook error: … BLOCKED`, joined back to the originating `tool_use_id`.

**Measurement limit, stated up front:** a hook that exits 0 silently leaves *no* transcript trace.
Everything below counts hooks that **emitted**. Absence of an emission is not proof a hook did not
run.

---

## 1. Reach — the stack lands in subagent context

| tier | transcripts (30d) | carrying a stack hook emission | share |
|---|---:|---:|---:|
| main thread | 202 | 196 | **97.0%** |
| subagent (`subagents/agent-*.jsonl`) | 1,593 | 1,548 | **97.2%** |
| Workflow worker | 0 in window | — | — |

120-day window, needed for the Workflow tier:

| tier | transcripts (120d) | carrying a stack hook emission | share |
|---|---:|---:|---:|
| main thread | 551 | 538 | 97.6% |
| subagent | 3,123 | 2,839 | 90.9% |
| Workflow worker | 820 | 515 | **62.8%** |

## 2. `PreToolUse` hard gates DO fire inside subagents

Stack-fingerprinted **gate** (blocking) emissions, 30-day window:

| hook | main | subagent |
|---|---:|---:|
| `ctx-execute-enforcer` | 1,059 | **1,462** |
| `cmm-grep-nudge` (BLOCKED: Use CMM tools) | 60 | **112** |
| `cwd-guard` | 61 | 29 |
| `ctx-execute-cmm-nudge` | 13 | 14 |
| `session-gate` | 21 | 8 |
| `grep-cmm-gate` | 1 | 2 |
| `agent-cmm-gate` (`PreToolUse:Agent`) | 64 | 8 |

Worked example — the CMM gate blocking a code search made *inside* a subagent
(`-Users-ahby-Sources-atm-sqlite/79e4c110…/subagents/agent-a2e558f8491d4debc.jsonl`):

```
version=2.1.228  ts=2026-08-15T17:08:02.007Z  isSidechain=True
blocked tool: Bash
  command: grep -rn --include='*.pm' --include='*.pl' … "ApTest::SQLiteFile" .
PreToolUse:Bash hook error: [bash /Users/ahby/Sources/atm_sqlite/.claude/hooks/cmm-grep-nudge.sh]:
BLOCKED: Use CMM tools instead of Bash navigation for code search.
  - Symbol search:  mcp__codebase-memory-mcp__search_graph(name_pattern=…)
```

`isSidechain: true` — the tool call was made inside the subagent, and the project's `PreToolUse`
hook blocked it and named the CMM replacement.

**No version boundary.** Gate emissions inside subagents appear on every Claude Code version in
the window — 2.1.220, .228, .233, .241, .247, .251, .258, .259 — and, in the 120-day window, back
through 2.1.175. This is not "recently fixed"; it has been working across the whole corpus.

## 3. Workflow workers are also gated — except at the spawn

120-day window, gate emissions inside `subagents/workflows/*/agent-*.jsonl`:

| hook | emissions |
|---|---:|
| `cwd-guard` | 347 |
| `cmm-grep-nudge` | 231 |
| `ctx-execute-enforcer` | 154 |
| `index-root-gate` | 19 |
| `grep-cmm-gate` | 5 |
| `session-gate` | 1 |

The repo's claim splits in two:

- ❌ **"`PreToolUse` hooks do not fire inside a Workflow-spawned worker" — false.** 757 gate
  emissions inside Workflow worker transcripts say otherwise.
- ✅ **"A Workflow-spawned worker bypasses `agent-cmm-gate.sh`" — true, by matcher construction.**
  That gate is `PreToolUse:Agent`; a Workflow spawn is a `Workflow` tool call and cannot match.
  Empirically, in main-thread transcripts over 120 days: **163 `Workflow` tool calls, 0 with an
  `agent-cmm-gate` attachment**, against 1,477 `Agent` calls of which 183 were gated. (The Agent
  rate is only 12% because the gate blocks only prompts that omit CMM references.)

## 4. `SubagentStart` injection is surfaced

30-day window, subagent tier: **2,210 `subagent-cmm-startup` injections** and 2,210
`subagent-ctx-startup` injections. The 2,211 "Invoke Skill('cmm-rules')" matches are *the same
attachments* — `subagent-cmm-startup.sh` embeds that directive in its `additionalContext` — not a
third stream. (Main-tier `skill-nudge`, 304 in 30d, *is* a separate hook: `user-prompt-submit`.)

~2,210 is almost certainly the 2,212 you counted. `cmm-agent-preamble.md`'s "empirically not
surfaced/actioned by either Task or Workflow workers" is wrong on **surfaced**. It says nothing
about **actioned** — that is section 6.

---

## 5. Adoption — reach does not produce behaviour

**Coverage.** Of tool calls that *should* draw a stack hook (a `Grep`; a `Read` of a code-extension
file; a `Bash` whose command is exploration-shaped — grep/rg/find/cat/sed/awk/ls/head/tail), how
many actually drew one on the same `tool_use_id`:

| tier | eligible calls | covered | rate |
|---|---:|---:|---:|
| main (30d) | 3,370 | 595 | 17.7% |
| subagent (30d) | 2,645 | 963 | 36.4% |
| Workflow (120d) | 5,152 | 388 | 7.5% |

Subagents are covered **at least as well as the main thread**. (Not "twice as well" — the subagent
corpus is dominated by QA-reviewer agents doing heavy `Bash`, which `ctx-execute-enforcer` catches
broadly, while main-thread eligible calls skew toward `Read`, which is nudged rather than gated.
The direction is reliable; the ratio is not.) Whatever the enforcement gap is, it is not "hooks
can't see inside subagents".

**Tool mix in stack-enabled transcripts:**

| tier | tool calls | CMM | ctx | raw | CMM% | ctx% |
|---|---:|---:|---:|---:|---:|---:|
| main (30d) | 36,185 | 1,064 | 14,859 | 8,199 | 2.9% | 41.1% |
| subagent (30d) | 27,622 | 2,853 | 13,100 | 6,273 | 10.3% | 47.4% |
| Workflow (120d) | 9,582 | 1,662 | 884 | 5,627 | 17.3% | 9.2% |

## 6. The redirect — per gate, what the next call is after a block

Aggregating all gates together is misleading, because `ctx-execute-enforcer` is ~90% of all blocks
and it never asks for CMM. Split by the gate that fired (30-day window, n ≥ 10):

| tier | gate | n | → CMM | → ctx | → raw | → other |
|---|---|---:|---:|---:|---:|---:|
| main | `ctx-execute-enforcer` | 1,057 | 1.0% | **50.1%** | 29.9% | 18.9% |
| subagent | `ctx-execute-enforcer` | 1,439 | 1.8% | **36.6%** | 33.0% | 28.6% |
| subagent | `cmm-grep-nudge` | 112 | **25.0%** | 34.8% | 36.6% | 3.6% |
| main | `cmm-grep-nudge` | 61 | **13.1%** | 6.6% | 73.8% | 6.6% |
| main | `ctx-execute-cmm-nudge` | 13 | 15.4% | 76.9% | 0.0% | 7.7% |
| subagent | `ctx-execute-cmm-nudge` | 13 | 23.1% | 46.2% | 15.4% | 15.4% |
| main | `cwd-guard` | 61 | 1.6% | 1.6% | 95.1% | 1.6% |
| subagent | `cwd-guard` | 29 | 0.0% | 10.3% | 89.7% | 0.0% |

120-day window confirms the shape and adds the Workflow tier: `cmm-grep-nudge` → CMM is 20.9%
(subagent, n=350), 17.7% (Workflow, n=231), 7.1% (main, n=281).

Two things follow:

- **Both gates work, in the direction they point.** `ctx-execute-enforcer` converts 36–50% of
  blocks into a `ctx_*` call. `cmm-grep-nudge` converts 13–25% into a CMM call — lower, but an
  order of magnitude above the 2–3% baseline you get from gates that don't name CMM.
- **The CMM gate converts better inside subagents (25%) than on the main thread (13%).** The
  transcripts do not support "guidance doesn't land on subagents". If anything the reverse.
- Still, 33–74% of blocked calls go straight back to `Read`/`Bash`. That is the real gap.

**Transcripts that never touch CMM despite the stack firing** (≥5 tool calls):

| tier | transcripts | zero CMM | zero ctx |
|---|---:|---:|---:|
| main (30d) | 187 | 24 (12.8%) | 19 (10.2%) |
| subagent (30d) | 1,527 | **795 (52.1%)** | 22 (1.4%) |
| Workflow (120d) | 379 | 143 (37.7%) | 310 (81.8%) |

---

## Conclusions

1. **The `#34692` claim is stale and should be removed.** `PreToolUse` hooks fire inside both Task
   subagents and Workflow workers, on every Claude Code version across a 120-day corpus.
2. **`SubagentStart` injection is surfaced**, ~2,210 times in 30 days. Drop "not a reliable
   behavioral lever" as a statement about *delivery*.
3. **Keep the `agent-cmm-gate` bypass wording** — a Workflow spawn genuinely does not hit
   `PreToolUse:Agent` (163 Workflow calls, 0 gated). Scope it to that one gate.
4. **Keep the preamble requirement, change its justification.** The reason to bake CMM/ctx guidance
   into every `agent()` prompt is not that hooks can't reach the agent. It is that 52% of gated
   subagent transcripts still make zero CMM calls, and 33–74% of blocked calls go straight back to
   `Read`/`Bash`. Reach is solved; adoption is not.
5. **Design lesson for the gate messages.** The strongest predictor of a useful redirect is whether
   the block names the replacement call concretely. `ctx-execute-enforcer` ("route this through
   `ctx_execute`") converts at 36–50%; `cmm-grep-nudge`, which names `search_graph(name_pattern=…)`
   generically, converts at 13–25%; `cwd-guard`, which names no alternative, converts at ~0% and
   sends 90–95% of blocks straight back to `Bash`. Making the CMM gate echo the *specific* symbol
   or pattern from the blocked command into a ready-to-run `search_graph` call is the highest-value
   change available.

## Side finding — `cmm-grep-nudge` false positives

Three of the first four sampled `cmm-grep-nudge` blocks were not code searches at all:
`git log origin/x..HEAD --oneline | cat`, `git diff --stat | cat`, and a `grep` scoped to one named
file. The `| cat` suffix appears to be what trips the matcher. Blocking `git log` as "code search"
is friction with no CMM alternative, and plausibly contributes to the 74% back-to-raw rate on the
main thread. Worth a separate look at `hooks/global/cmm-grep-nudge.sh`.

---

## Baseline — anti-pattern rates before any gate change (2026-09-03, 30 days)

Recorded so the effect of `ctx-payload-guard` can be judged against something. Produced by
`make measure`; 1,799 transcripts. **STRONG** = `cmd | head/tail` or stdout-to-file (unambiguous
output suppression). **WEAK** = `sed -n 'a,bp'`, `awk 'NR<=N'`, `grep -m N` (line-range extraction,
often a legitimate computed excerpt).

| surface | shell payloads | STRONG | caught by a hook | WEAK |
|---|---:|---:|---:|---:|
| `Bash` | 8,720 | 19.0% | **28.6%** | 5.0% |
| `ctx_execute` | 21,436 | **24.3%** | **0.1%** (7 of 5,214) | 16.8% |
| `ctx_execute_file` | 86 | 20.9% | 0.0% | 16.3% |
| `ctx_batch_execute` | 19,607 | 7.4% | 0.0% | 13.9% |

`intent=` is on 32.1% of shell `ctx_execute` calls, and truncation is essentially as likely with it
(25.3%) as without (23.9%) — the intended alternative is not displacing the anti-pattern.

Bash-only syntax in `language="shell"` payloads, which run `$SHELL` (zsh here), not bash:
`${!var}` 141, unquoted word-split `for` 38, `mapfile`/`readarray` 4, `read -a` 2,
`declare -n` 1, `${var^^}` 1.

**Reading the after-shot:** success is STRONG falling **without** WEAK rising to absorb it. Once
`| head` is gated, the cheapest evasion is `sed -n '1,60p'`, and WEAK is already 3,147 occurrences
in `ctx_execute` — a migration would look like a win in the STRONG column alone.

> **Detector revisions — read this before comparing to an earlier draft.** These figures are tighter
> than this session's first drafts (34.1% for `ctx_execute`) because the shipped detector scrubs
> quoted spans, `$( )`, backticks and heredoc bodies before scanning, and applies a file-descriptor
> rule so `2> err.log`, `2>/dev/null`, `2>&1` and `>&2` are not counted while `1> out.log` is.
>
> They are tighter again than the **first committed** baseline (27.8%), which was measured with a
> `stdout-to-file` detector carrying three defects. Re-running both detectors over the *same* corpus
> isolates each one — `stdout-to-file` on `ctx_execute`, 492 → 330:
>
> | change | Δ | why |
> |---|---:|---|
> | quoted spans filled with `_`, not spaces | **−136** | the dominant defect, and it cut **both** ways |
> | redirect target may not cross a newline | 0 | correct, but no payload in the corpus hit it |
> | shell `#` comments scrubbed | −18 | `# note -> here` read as a redirect to a file `here` |
> | `echo` after `do`/`then`/`else` is authoring | −8 | `for i in …; do echo x > "f$i"; done` |
>
> The first row is worth stating precisely, because "quoted targets were invisible" is the natural
> guess and it is wrong. Blanking a quoted span to **spaces** did not remove the redirect — it
> removed the *target*, and `\s*` in the target pattern then skipped the blanks and bound the **next
> word** instead. `: > "$tmp/empty"; mkdir "$tmp/dir"` bound `mkdir`. So the old count both missed
> real quoted-target redirects and invented phantom ones against whatever token followed; the net
> was an overcount of 162. Filling with `_` keeps the token intact, so the `/dev/null`,
> target-reused-later and authoring exclusions finally evaluate the file the payload actually names.
>
> Direction and conclusions are unchanged: `ctx_execute` remains the largest anti-pattern surface
> and is still essentially ungated (0.1%). `make measure` after WS1 must be compared against **this**
> table, not the 27.8% one — the detector, not just the behaviour, changed underneath it.

## Caveats

- Silent `exit 0` hooks are invisible; only emissions are counted.
- The "raw" bucket counts all `Bash`/`Read`/`Grep`/`Glob`, including legitimate non-code work, so
  it overstates avoidable exploration.
- The "eligible call" denominator is a heuristic (extension list + command regex), so coverage
  rates are approximate; the main-vs-subagent *comparison* is the reliable part, since both use the
  same heuristic.
- "Next call after a block" is a proxy for behaviour change, not proof of causation.
- Single-user corpus, one machine.
- Workflow-tier numbers come from the 120-day window.
