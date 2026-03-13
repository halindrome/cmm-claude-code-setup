---
phase: "04"
plan: "04"
title: "Write rules/allowed-tools.txt"
wave: 1
depends_on: []
must_haves:
  - All 14 CMM tool names with mcp__codebase-memory-mcp__ prefix
  - One tool per line
  - Header comment with JSON conversion format
---

# Plan 04: Write `rules/allowed-tools.txt`

## Output File
`rules/allowed-tools.txt`

## Purpose
Plain text file listing all 14 codebase-memory-mcp tool names (with full MCP prefix), one per line. Users convert this list to a JSON array for `.claude/settings.local.json` under `"allowedTools"`.

## Tasks

### Task 1: Create `rules/allowed-tools.txt`

Write the file with a header comment block followed by 14 tool names, one per line.

**Exact content:**

```
# codebase-memory-mcp — allowed tools
#
# Add these to .claude/settings.local.json under "allowedTools":
#
#   {
#     "allowedTools": [
#       "mcp__codebase-memory-mcp__index_repository",
#       "mcp__codebase-memory-mcp__index_status",
#       ...
#     ]
#   }
#
# One tool per line below:

mcp__codebase-memory-mcp__index_repository
mcp__codebase-memory-mcp__index_status
mcp__codebase-memory-mcp__list_projects
mcp__codebase-memory-mcp__delete_project
mcp__codebase-memory-mcp__get_architecture
mcp__codebase-memory-mcp__get_graph_schema
mcp__codebase-memory-mcp__search_graph
mcp__codebase-memory-mcp__search_code
mcp__codebase-memory-mcp__query_graph
mcp__codebase-memory-mcp__get_code_snippet
mcp__codebase-memory-mcp__trace_call_path
mcp__codebase-memory-mcp__detect_changes
mcp__codebase-memory-mcp__manage_adr
mcp__codebase-memory-mcp__ingest_traces
```

### Key Design Points
- **Prefix**: All tools use `mcp__codebase-memory-mcp__` prefix (double underscores)
- **Count**: Exactly 14 tools
- **Order**: Grouped logically — indexing (4), architecture/schema (2), search (3), code nav (2), analysis (2), traces (1)
- **Header comment**: Shows the JSON format users need for `settings.local.json`
- **No trailing newline issues**: End file with a single newline after the last tool name
- **Plain text**: `#` comments at top, no other formatting
