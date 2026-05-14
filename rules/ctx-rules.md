## Context Mode (session memory)

Context-mode is a session-scoped FTS5 index over tool-call output. The PostToolUse hook (see below) automatically indexes ALL captured output regardless of whether you supplied an `intent`. The `intent=` parameter on `ctx_execute` / `ctx_execute_file` is a SEARCH-MODE TRIGGER, not an indexing toggle: when output exceeds `INTENT_SEARCH_THRESHOLD = 5_000` bytes (~80–100 lines) AND `intent` is provided, the tool returns FTS5 search hits + section titles instead of the raw output. Below the 5KB threshold the raw output is returned inline whether or not `intent` is set. Indexing happens either way.

### PostToolUse capture (always on)

When context-mode is installed via `setup.sh --project` (phase 51+), an upstream PostToolUse hook indexes every Bash, Read, Grep, Glob, Write, Edit, and `mcp__*` tool result into the session FTS5 store automatically — no `intent=` parameter needed on `ctx_execute`. The retrieval protocol below therefore applies to ALL captured output, not just explicit `ctx_execute` calls.

| Tool | Purpose |
|------|---------|
| `ctx_execute` | Run a shell/JS/TS/Python/etc. command in a sandboxed subprocess; only stdout enters context. Pass `intent=` to switch to search-mode return when output > 5KB. |
| `ctx_execute_file` | Like `ctx_execute` but takes a file path; the raw file stays in the sandbox while only your computed result returns. **Preferred over `ctx_execute` for shell scripts longer than ~50 lines** or scripts with significant inline content that would inflate the `ctx_execute` `code` payload. Also use whenever the input is a file you would otherwise Read just to feed into analysis. |
| `ctx_index` | Index arbitrary text (notes, pasted snippets) under a descriptive source label so it becomes searchable via `ctx_search`. |
| `ctx_search` | Full-text search across everything indexed this session; always try this before re-running a command. |
| `ctx_fetch_and_index` | Fetch a URL and index the response body; preferred over `ctx_execute("curl ...")` because it caches and indexes for free. |
| `ctx_batch_execute` | Run several commands in one call and search the combined output. Each command requires a `label` field (used as the FTS5 chunk title — promote from "descriptive" to "required"). Pass `concurrency: 1-8` (default 1) for I/O-bound parallelism (gh API, curl, multi-repo git reads); keep `concurrency: 1` for CPU-bound or stateful commands (npm test, build, lint, port-bound servers). *(`concurrency` requires context-mode v1.0.104+; absent in installed v1.0.75 — agents on the installed binary must omit the parameter.)* |
| `ctx_stats` | Report what is currently indexed (sources, token counts, age) plus lifetime token-savings dashboard. |
| `ctx_doctor` | Run server-side diagnostics; use when hooks or FTS5 seem broken. Returns a markdown checklist with PASS/FAIL per check. |
| `ctx_upgrade` | Upgrade context-mode in-place. Operator use only — agents should not call this spontaneously without user direction. |
| `ctx_purge` | **Destructive: clears all indexed session content.** Agents must NOT suggest this casually; reserved for explicit user-initiated cleanup. Same caution category as `rm -rf` — irreversible, never invoke without an explicit user request. |
| `ctx_insight` | Open the analytics dashboard in a browser; not useful in non-interactive sessions. *(Requires context-mode v1.0.107+; absent in installed v1.0.75.)* |

### Retrieval protocol

Before `ctx_execute` on a topic you have already investigated this session, try `ctx_search(queries=["<topic>"])` first. If it returns useful hits, read them instead of re-running the command. Aim for roughly one `ctx_search` per 3-5 indexing operations (`ctx_execute` with intent / `ctx_index` / `ctx_fetch_and_index`) — if you have indexed five things without searching once, you are almost certainly re-fetching something you already have. Because PostToolUse capture is always on (see above), this applies to any prior Bash/Read/Grep/WebFetch command this session — not only explicit `ctx_execute` calls.

Use `ctx_execute_file` when the input is a file path and you want the raw file to stay out of context — pass the file path plus the analysis code, and only your computed result returns.

### Prefer

Prefer `ctx_fetch_and_index` over `ctx_execute("curl ...")` for URL fetches — you get caching and indexing for free. When spawning in an established session, call `ctx_stats` first to see what is already indexed before deciding what to fetch or run.

### Anti-patterns

- **Never use output-truncation primitives (`head -N`, `tail -N`, `sed -n '1,Np'`, `grep -m N`, `awk 'NR<=N'`) to cap large command output in captured shell commands.** PostToolUse indexes both `ctx_execute` and plain Bash output automatically — bytes discarded before capture are permanently lost and unsearchable. Exception: bare `head file` / `tail file` (reading a small file directly) is fine; only the `cmd | head -N` pipe-to-truncate pattern is the anti-pattern. When `intent=` is set and output exceeds ~5 KB, `ctx_execute` switches to FTS5 search-mode return with no context-size penalty; below that threshold raw output enters context — write programmatic analysis either way: filter, count, and extract in code, then print only the findings. This rule applies equally to `ctx_execute`, `ctx_execute_file`, and `ctx_batch_execute`. It is advisory — no PreToolUse hook enforces it on sandbox payloads; compliance depends on the agent following the guideline.
