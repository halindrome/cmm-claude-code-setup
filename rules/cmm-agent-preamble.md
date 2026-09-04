# CMM / Context-Mode subagent preamble

**Canonical, reusable instruction block for subagent prompts.** Paste the region
between the `--- copy from here ---` / `--- copy to here ---` markers verbatim
into every subagent prompt you author:

- each `agent()` prompt in a **Workflow** script (`parallel()` / `pipeline()`
  lens agents included), and
- the body of any `.claude/agents/*.md` **agent definition** used as an
  `agentType` / `subagent_type`.

## Why the prompt still matters, even though hooks do reach the agent

Hooks **do** reach inside a running subagent. Measured over 1,798 Claude Code
transcripts (30 days, 2026-09-03):

- `PreToolUse` gates fire on tool calls made *inside* a subagent — 1,462
  `ctx-execute-enforcer` and 112 `cmm-grep-nudge` hard blocks landed on
  sidechain (`isSidechain: true`) calls, on every Claude Code version from
  2.1.175 through 2.1.260. Workflow-spawned workers are gated too.
- `SubagentStart` `additionalContext` **is** delivered — ~2,210 injections per
  30 days.
- The one real bypass is narrow: `agent-cmm-gate.sh` is `PreToolUse:**Agent**`,
  so a Workflow-spawned worker (a `Workflow` call) never matches it — 163
  `Workflow` calls, 0 gated. That is the **spawn** check only; the worker's own
  tool calls are still gated.

Delivery is not the problem. **Adoption is.** 52% of gated subagent transcripts
making 5+ tool calls still issue zero CMM calls, and only 13–25% of blocked code
searches are followed by a CMM call — a blocked `Grep` becomes a `Read` far more
often than it becomes a `search_graph`. A hook can stop one tool call; it does
not change the agent's strategy for the next one.

The prompt is where strategy is set. Bake this in.

--- copy from here ---

**Code navigation (MANDATORY): use codebase-memory-mcp (CMM) graph tools, not raw file reads.**
- `search_graph` — find functions/classes/modules by name pattern (NEVER grep to find a definition)
- `get_code_snippet` — fetch a symbol's exact source by qualified name
- `trace_path` — who calls X / what X calls (use for downstream-consumer and call-chain checks)
- `get_architecture` — orient in an unfamiliar area (packages, hotspots, routes)
- `query_graph` — Cypher graph queries (complexity metrics, cross-cutting patterns)
- `search_code` — graph-augmented text search for string literals, error messages, TODOs
Orient first: `get_architecture` → `search_graph` → `get_code_snippet`. Any symbol-existence
claim MUST cite the definition site from `get_code_snippet` / `search_graph`, not a grep hit.
Full `Read` only for: non-code files, files under ~50 lines, or files not yet indexed.

**Large output / long commands (when Context Mode is available): keep bytes out of your window.**
- `ctx_execute` / `ctx_execute_file` — run analysis in a sandbox; only what you print returns
- `ctx_batch_execute` — run several commands in one call; search the combined output
- `ctx_search` — search everything indexed this session BEFORE re-running a command
- `ctx_fetch_and_index` — fetch a URL (indexed + cached) instead of `curl`
Route large diffs, whole-file reads, test-suite runs, and multi-file scans through these so your
findings — not the raw bytes — enter context. On a big diff this preserves your own token budget.
Do NOT pipe into `head`/`tail` or redirect stdout to a file: those discard bytes before they are
indexed. Pass `intent="<your question>"` instead — output over 5KB flips to search-mode for free.

**`language="shell"` runs `$SHELL` (zsh here), NOT bash.** `language="bash"` is not a distinct
runtime and cannot select bash. `${!var}` is bash-only — zsh spells it `${(P)var}` and otherwise
answers `bad substitution`. `mapfile`/`readarray`/`declare -n` do not exist; `${var^^}`/`${var,,}`
are `${var:u}`/`${var:l}`; arrays are 1-indexed. Worst, zsh does not word-split an unquoted `$var`,
so `for f in $files` silently iterates once over the whole string. Need bash? `bash -c '…'`.

--- copy to here ---
