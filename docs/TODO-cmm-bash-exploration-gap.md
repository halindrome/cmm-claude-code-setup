# TODO — Close the CMM-adoption gap (Bash/Read exploration slips the grep gate)

**Status:** proposed / not started
**Created:** 2026-06-05
**Origin:** investigation session in sibling repo `/Users/ahby/Sources/cvx_6033` (Corvex monorepo)
**Owner repo for the fix:** this one (`cmm-claude-code-setup`) — source of the hooks/agents/rules.

---

## Background / why

The CMM-integration stack is meant to push agents toward CMM-first navigation (`get_architecture` → `search_graph` → `get_code_snippet`) instead of raw filesystem grepping. In a controlled experiment it only *half* worked.

## The evidence

On 2026-06-05 we ran a 4-Scout `vbw:vbw-scout` codebase map (via the Workflow tool) over the Corvex monorepo and measured each Scout's actual tool use from its transcript + the CMM call counter:

| Scout (domain) | CMM calls | Raw explore | CMM-first? | Verdict |
|---|---|---|---|---|
| tech-stack | 6 (list_projects, get_architecture, search_code×4) | 12 Bash | yes | strong CMM |
| architecture | 4 (list_projects, get_architecture, query_graph×2) | 7 Bash | yes | strong CMM |
| quality | **0** | 11 Read + 6 Bash | no | bypassed CMM |
| concerns | **0** | 9 Bash | no | bypassed CMM |

For **all 4** agents: `SubagentStart` CMM-state injection fired **and** the `PreToolUse` cmm-grep gate fired (≥1 `BLOCKED: Use CMM tools` each). So enforcement *reached* every agent — yet 2 of 4 used zero CMM and got their work done entirely through `Read` + `Bash`.

## Root cause

The enforcement is **advisory where it matters most**:

- The hard block (`hooks/global/cmm-grep-nudge.sh`) covers the **`Grep` tool** and **grep-shaped `Bash`**. But `Bash` invoking `find` / `cat` / `ls -R` / `awk` / `sed` for exploration **slips through** — the concerns Scout did everything in 9 Bash calls; the quality Scout fell back to 11 `Read`s after its grep was blocked.
- `Read` is only *nudged* (`hooks/global/cmm-nudge.sh`), never blocked, so an agent can read its way around CMM freely.
- The Scout agent prompt (`agents/vbw-scout.md`) *mentions* CMM availability but doesn't *insist* on orient-first before any raw exploration.

Net: when grep is blocked, agents pivot to Read/Bash instead of to `search_graph` — the gate redirects the *tool* but not the *behavior*.

## Goal

Make CMM-first navigation close to universal for indexed repos, without making the hooks so aggressive they block legitimate non-code file work (configs, JSON, markdown, small files).

## Proposed levers (low → high friction)

1. **Strengthen the Scout prompt (lowest risk, do first).** In `agents/vbw-scout.md`, add an explicit ordering directive: "For any indexed codebase, you MUST orient with `get_architecture` and use `search_graph`/`search_code`/`trace_path` BEFORE any `Read`/`Bash`/`find`/`cat` exploration of source. Raw file reads are for non-code files, full-file context, or fetching a specific snippet CMM pointed you to." Mirror into the other agent defs (`vbw-lead.md`, `vbw-dev.md`, `vbw-debugger.md`) as appropriate.
2. **Extend the Bash matcher** in `hooks/global/cmm-grep-nudge.sh` to also catch recursive/exploratory shell patterns over source trees: `find … -name '*.<codeext>'`, `cat`/`sed -n`/`awk` on source files, `ls -R`. Keep it advisory-with-redirect (point to `search_graph`/`search_code`), and **exempt** non-code paths, small files, and the existing `# cmm-exempt` bypass so config/markdown/JSON work isn't gated. Risk: false positives + friction; tune carefully and keep the bypass prominent.
3. **(Optional) Promote the Read nudge toward a soft gate** for source files in indexed projects — e.g. after N raw Reads without a CMM call, escalate the nudge. Higher friction; only if 1+2 prove insufficient.
4. **Note: ctx/context-mode was used by _none_ of the 4 Scouts** — the ctx counter stayed empty. Separately consider whether Scouts should be nudged toward `ctx_*` for large command output (or whether that's fine to leave optional). Track as a sub-item, not a blocker.

## Files likely to touch (this repo)

- `agents/vbw-scout.md` (+ peers) — orient-first directive.
- `hooks/global/cmm-grep-nudge.sh` — broaden Bash exploration matcher (with non-code exemptions + `# cmm-exempt` bypass intact).
- `hooks/global/cmm-nudge.sh` — optional Read escalation.
- `rules/cmm-rules.md` — document the strengthened expectation.
- `tests/` — add/adjust hook tests for the new matchers (don't regress the markdown/config exemptions).
- `CHANGELOG.md`, version files — bump.

## Acceptance criteria

- Re-running the 4-Scout map experiment, **≥3 of 4** (ideally 4/4) Scouts make at least one CMM navigation call and orient via `get_architecture` before raw source exploration.
- Bash `find`/`cat` over source triggers the redirect; the same commands over `.md`/`.json`/config and the `# cmm-exempt` escape hatch still pass.
- No regression in the existing hook test suite (markdown/config/small-file exemptions preserved).

## How to verify

- Reproduce the map fan-out (see companion `TODO-workflow-team-replacement.md`).
- Compare per-Scout CMM-vs-raw tool mix from `…/subagents/workflows/<runId>/agent-*.jsonl` and the delta in `~/.cache/codebase-memory-mcp/_call-counts-<md5>.json` before/after.
- Confirm `BLOCKED`/redirect lines now also appear for exploratory `find`/`cat` on source, but NOT for config/markdown.

## Caveat

Don't over-tighten. The whole point of the advisory style (see `docs/hook-advisory-style.md`) is to guide without blocking legitimate work. The fix should raise CMM adoption while keeping the non-code and `# cmm-exempt` paths frictionless.
