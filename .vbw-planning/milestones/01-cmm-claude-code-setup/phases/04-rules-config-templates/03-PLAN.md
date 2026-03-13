---
phase: "04"
plan: "03"
title: "Write rules/mcp-example.json"
wave: 1
depends_on: []
must_haves:
  - Valid JSON with mcpServers key
  - codebase-memory-mcp server registration
  - type stdio
  - Empty args array
---

# Plan 03: Write `rules/mcp-example.json`

## Output File
`rules/mcp-example.json`

## Purpose
Minimal JSON for project root `.mcp.json`. Registers the codebase-memory-mcp MCP server so Claude Code can discover and use it.

## Tasks

### Task 1: Create `rules/mcp-example.json`

Write the following exact JSON content:

```json
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "command": "codebase-memory-mcp",
      "args": [],
      "type": "stdio"
    }
  }
}
```

### Key Design Points
- **Server name**: `codebase-memory-mcp` (matches the binary name)
- **Command**: `codebase-memory-mcp` — assumes binary is on PATH (installed via `codebase-memory-mcp install`)
- **Args**: Empty array — no arguments needed
- **Type**: `stdio` — standard I/O communication protocol
- **No absolute paths**: The install script puts the binary on PATH
- **Single server**: Only one MCP server entry (unlike jmunch which has two)
- **Valid JSON**: Pretty-printed with 2-space indent, no trailing commas

### Task 2: Validate JSON syntax

After writing, verify the file is valid JSON.
