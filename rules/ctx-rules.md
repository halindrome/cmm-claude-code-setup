## Context Mode (session memory)

Context-mode is a session-scoped FTS5 index over tool-call output — every `ctx_execute` with an `intent`, every `ctx_index`, and every `ctx_fetch_and_index` writes its captured text into a searchable store you can query later without re-running the command.

### PostToolUse capture (always on)

When context-mode is installed via `setup.sh --project` (phase 51+), an upstream PostToolUse hook indexes every Bash, Read, Grep, Glob, Write, Edit, and `mcp__*` tool result into the session FTS5 store automatically — no `intent=` parameter needed on `ctx_execute`. The retrieval protocol below therefore applies to ALL captured output, not just explicit `ctx_execute` calls.

- `ctx_execute` — run a shell command; pass `intent` to index the output for later retrieval
- `ctx_search` — full-text search across everything indexed this session; always try this before re-running a command
- `ctx_index` — index arbitrary text (notes, pasted snippets) under an intent label
- `ctx_fetch_and_index` — fetch a URL and index the response body; preferred over `ctx_execute("curl ...")`
- `ctx_batch_execute` — run several commands in one call; each child step may carry its own `intent`
- `ctx_stats` — report what is currently indexed (intents, token counts, age)

### Retrieval protocol

Before `ctx_execute` on a topic you have already investigated this session, try `ctx_search(queries=["<topic>"])` first. If it returns useful hits, read them instead of re-running the command. Aim for roughly one `ctx_search` per 3-5 indexing operations (`ctx_execute` with intent / `ctx_index` / `ctx_fetch_and_index`) — if you have indexed five things without searching once, you are almost certainly re-fetching something you already have. Because PostToolUse capture is always on (see above), this applies to any prior Bash/Read/Grep/WebFetch command this session — not only explicit `ctx_execute` calls.

### Prefer

Prefer `ctx_fetch_and_index` over `ctx_execute("curl ...")` for URL fetches — you get caching and indexing for free. When spawning in an established session, call `ctx_stats` first to see what is already indexed before deciding what to fetch or run.
