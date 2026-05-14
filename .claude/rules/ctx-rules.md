## Context Mode (session memory)

Context-mode is a session-scoped FTS5 index over tool-call output — every `ctx_execute` with an `intent`, every `ctx_index`, and every `ctx_fetch_and_index` writes its captured text into a searchable store you can query later without re-running the command.

### PostToolUse capture (always on)

When context-mode is installed via `setup.sh --project` (phase 51+), an upstream PostToolUse hook indexes every Bash, Read, Grep, Glob, Write, Edit, and `mcp__*` tool result into the session FTS5 store automatically — no `intent=` parameter needed on `ctx_execute`. The retrieval protocol below therefore applies to ALL captured output, not just explicit `ctx_execute` calls.

Upstream context-mode (v1.0.122) exposes 11 MCP tools — 6 sandbox tools and 5 meta-tools.

Sandbox tools (run code, capture output, write into the FTS5 store):

- `ctx_execute` — run a shell command; pass `intent` to index the output for later retrieval
- `ctx_execute_file` — run a script file (preferred over `ctx_execute` for shell scripts longer than ~50 lines, or scripts with significant inline content that would inflate the `ctx_execute` `code` payload). Output is captured the same way as `ctx_execute`.
- `ctx_search` — full-text search across everything indexed this session; always try this before re-running a command
- `ctx_index` — index arbitrary text (notes, pasted snippets) under an intent label
- `ctx_fetch_and_index` — fetch a URL and index the response body; preferred over `ctx_execute("curl ...")`
- `ctx_batch_execute` — run several commands in one call; each child step may carry its own `intent`

Meta-tools (session/install diagnostics and management):

- `ctx_stats` — report what is currently indexed (intents, token counts, age)
- `ctx_doctor` — diagnostics — inspect session-mode/MCP/hook state when something looks wrong
- `ctx_upgrade` — upgrade — manage the installed context-mode build (npm-form installs)
- `ctx_purge` — **Destructive: clears all indexed session content. Agents must NOT suggest this casually; reserved for explicit user-initiated cleanup.** Same caution category as `rm -rf` — never invoke without an explicit user request.
- `ctx_insight` — analytics — 90-metric / 23-category session insight dashboard (user-facing; not a routing target)

### Retrieval protocol

Before `ctx_execute` on a topic you have already investigated this session, try `ctx_search(queries=["<topic>"])` first. If it returns useful hits, read them instead of re-running the command. Aim for roughly one `ctx_search` per 3-5 indexing operations (`ctx_execute` with intent / `ctx_index` / `ctx_fetch_and_index`) — if you have indexed five things without searching once, you are almost certainly re-fetching something you already have. Because PostToolUse capture is always on (see above), this applies to any prior Bash/Read/Grep/WebFetch command this session — not only explicit `ctx_execute` calls.

### Prefer

Prefer `ctx_fetch_and_index` over `ctx_execute("curl ...")` for URL fetches — you get caching and indexing for free. When spawning in an established session, call `ctx_stats` first to see what is already indexed before deciding what to fetch or run.

### Anti-patterns

- **Never use output-truncation primitives (`head -N`, `tail -N`, `sed -n '1,Np'`, `grep -m N`, `awk 'NR<=N'`) to cap large command output in captured shell commands.** PostToolUse indexes both `ctx_execute` and plain Bash output automatically — bytes discarded before capture are permanently lost and unsearchable. Exception: bare `head file` / `tail file` (reading a small file directly) is fine; only the `cmd | head -N` pipe-to-truncate pattern is the anti-pattern. When `intent=` is set and output exceeds ~5 KB, `ctx_execute` switches to FTS5 search-mode return with no context-size penalty; below that threshold raw output enters context — write programmatic analysis either way: filter, count, and extract in code, then print only the findings.
