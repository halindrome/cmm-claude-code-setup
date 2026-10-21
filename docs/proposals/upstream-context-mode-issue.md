# Upstream issue draft — context-mode

**Target:** <https://github.com/mksglu/context-mode/issues/new?template=feature_request.yml>
**Verified against:** `upstream/main` @ `a0d0322` (2026-08-25), `package.json` version `1.0.169`
**Companion:** `docs/proposals/ctx-truncation-enforcement.md` (the hook + rules changes, which stay in this repo)

> Everything asserted below was checked at the upstream tip, not against a local branch.
> Local checkout `/Users/ahby/Sources/context-mode` is 98 behind / 3 ahead of upstream;
> the `halindrome` fork is 428 behind. Neither was used as the source of truth.

---

## Title

`ctx_execute silently indexes nothing when a payload's stdout is filtered or redirected`

## Feature description

`ctx_execute` indexes the payload's **stdout**. Any payload that discards stdout before it
is emitted — `| head -N`, `| grep <pattern>`, or `> /tmp/file` — is indexed partially or not
at all. The tool returns a normal-looking success in every case, so the caller cannot tell
the difference between *"the command produced little output"* and *"I threw the output away
before you could capture it."*

There is no signal today. Confirmed at upstream tip: `src/server.ts` has no empty-stdout or
"nothing indexed" branch, and `hooks/routing-block.mjs` contains no guidance on truncation,
filtering, or redirection.

### Field evidence

A single long agent session (four MR review cycles plus a hardware install) used
`ctx_execute` for essentially every shell call, respected every hook block it hit, and still
discarded output dozens of times:

| Shape | Effect |
|---|---|
| `cmd \| tail -60`, `cmd \| head -40` | partial index |
| `cmd \| grep -E '^(PASS\|FAIL)'` (every test run) | near-total loss; discards more than `head -N` would |
| `ssh host 'cmd' > /tmp/x.log 2>&1` then analyse the file | **indexed nothing at all** |
| `docker ps … 2>/dev/null \| wc -l` | permission error became "0 containers" |

The redirect case is the important one. The agent adopted it *as a good-citizen
alternative* to `| head`, reasoning that writing to a file preserved the bytes. It does
preserve them on disk — and empties the payload's stdout, so context-mode captured nothing.
The tool reported success. That is a failure a caller cannot self-diagnose.

Two of these produced **wrong conclusions**, not merely lost bytes: a swallowed
docker-socket permission denial read as "zero containers running" on a healthy host, and the
same shape made a pre-install baseline reading report "not a mountpoint" when the truth was
"permission denied."

### Why a hook is not sufficient

`PreToolUse` hooks can inspect `tool_input.code`, and we are adding one downstream — and,
contrary to an earlier version of this argument, those hooks **do** fire inside subagents and
Workflow lens agents (measured across 1,798 transcripts, 2026-09-03: 1,462 `ctx-execute-enforcer`
and 112 `cmm-grep-nudge` blocks landed on sidechain calls, on every Claude Code version
2.1.175–2.1.260). Reach is not the gap.

The gap is that a hook is per-installation and per-platform. Our guard only protects repos where
`setup.sh` has been run and stays current — a drift check on 2026-09-03 found 5 of 15 active
sibling repos carrying hook copies between 2 and 5 months old. A server-side "nothing was indexed"
signal reaches every caller on every platform adapter with no install step and no drift, which is
why it is worth asking for even though the hook does run.

---

## Proposed solution

### 1. Primary — report when a payload produced no indexable stdout

When `ctx_execute` / `ctx_execute_file` / `ctx_batch_execute` complete with exit code `0`
and stdout that is empty or below a small threshold, include a line in the returned text:

```
Indexed 0 sections — this payload produced no stdout, so nothing was captured.
If the command's output was redirected (`> file`) or filtered (`| head`, `| grep`),
context-mode never saw it. Print to stdout and use intent= to control what returns.
```

Suggested refinement, if worth the complexity: only emit the hint clause when the payload
*text* contains a discarding shape (`>`, `| head`, `| tail`, `| grep`, `2>/dev/null`).
A payload that legitimately prints nothing then gets the bare factual line without the
lecture.

This is a **RETURNS-level fact**, not exhortation, so it sits comfortably inside ADR-0002.

### 2. Secondary — one line in `hooks/routing-block.mjs`

ADR-0002 §"Voice-of-trainer text … lives in `hooks/routing-block.mjs` and `CLAUDE.md`, not
in tool descriptions" designates this file as the correct layer, and it currently says
nothing about the topic. Suggested addition to the existing
`<context_window_protection>` guidance:

```
The payload's stdout IS the capture. Filtering it (`| head`, `| tail`, `| grep`) indexes
only what survives the filter; redirecting it (`> file`) indexes nothing at all while
appearing to succeed. Print everything and pass intent= — filtering on retrieval is
recoverable, filtering before capture is not.
```

### 3. Explicitly NOT proposed — tool-description wording

An earlier draft of this proposal wanted to add *"Print everything… do not pipe it through
head/tail/grep"* to the `ctx_execute` description. **Withdrawn.** ADR-0002 forbids the
tokens `NEVER`, `MANDATORY`, `FORBIDDEN`, `BLOCKED` and the phrase `Never use` (to be
expressed as `WHEN NOT:`), mandates the `WHEN → WHEN NOT → RETURNS → EXAMPLE` structure, and
enforces both via the contract test in `tests/core/server.test.ts`. That draft would have
failed the test on the forbidden-token rule, and the ADR is right: the description is a
selection cue, not a training surface.

If any description change is wanted at all, the only ADR-compatible form is a `RETURNS:`
clause noting that indexing covers stdout — which item 1 makes redundant by surfacing it at
runtime.

---

## Alternatives considered

- **Index stderr as well.** Would help the `2>/dev/null` case but not the redirect case, and
  changes capture semantics for every existing caller. Not proposed.
- **Reject payloads containing `>` outright.** Too blunt — a payload legitimately writing a
  file it then analyses is fine. The distinction is whether *the payload's own stdout* is
  emptied, which is what item 1 measures directly rather than guessing from source text.
- **Leave it to downstream rules.** This is what exists today; the field evidence above is a
  session that had those rules loaded, in a project that ships them, and violated them
  throughout. Rules that announce they are unenforced are the ones dropped under load.

---

## Environment

- context-mode `1.0.169` (upstream tip `a0d0322`, 2026-08-25)
- Claude Code, plugin form (`mcp__plugin_context-mode_context-mode__*`)
- macOS host; payloads targeting both macOS and Debian ARM64 over ssh

---

## Notes for whoever files this

- Keep the field-evidence table. The redirect-as-good-citizenship story is the part that
  makes the case, because it shows a *careful* caller reaching the wrong answer.
- Do not soften item 3 into "maybe also update the description" — citing the ADR and
  withdrawing the idea is what shows the issue was written against the project's own rules.
- Item 1 is the ask. Item 2 is cheap. If only one lands, it should be item 1, because it is
  the only one that reaches subagents.
