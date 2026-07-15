# CMM / Context-Mode subagent preamble

**Canonical, reusable instruction block for subagent prompts.** Paste the region
between the `--- copy from here ---` / `--- copy to here ---` markers verbatim
into every subagent prompt you author:

- each `agent()` prompt in a **Workflow** script (`parallel()` / `pipeline()`
  lens agents included), and
- the body of any `.claude/agents/*.md` **agent definition** used as an
  `agentType` / `subagent_type`.

## Why the prompt is the only place this lands

Hooks do **not** reach inside a running subagent:

- Claude Code issue [#34692](https://github.com/anthropics/claude-code/issues/34692):
  `PreToolUse` / `PostToolUse` hooks do **not** fire for tool calls made *inside*
  a subagent. The stack's enforcement gates (`ctx-execute-enforcer.sh`,
  `cmm-nudge.sh`, `grep-cmm-gate.sh`) therefore never touch a subagent's
  `Bash` / `Read` / `Grep` calls.
- `SubagentStart` `additionalContext` injection is not a reliable behavioral
  lever for subagents (empirically not surfaced/actioned by either Task or
  Workflow workers).
- `agent-cmm-gate.sh` (`PreToolUse:Agent`) enforces this preamble on the
  **main-thread `Agent` tool only**. A **Workflow-spawned worker bypasses that
  gate** — it surfaces as a `Workflow` call, not an `Agent` call.

So the subagent's **prompt** (and its `agentType` definition) is the ONLY place
this guidance provably lands. Bake it in; do not rely on hooks.

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

--- copy to here ---
