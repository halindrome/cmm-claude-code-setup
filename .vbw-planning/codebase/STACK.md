# Tech Stack

## Languages
- Markdown (documentation)

## Tooling
- **codebase-memory-mcp**: Node.js MCP server for code graph indexing
- **Claude Code**: Primary IDE / AI coding assistant
- **npm**: Package manager (global install for codebase-memory-mcp)

## MCP Servers
- **codebase-memory-mcp**: Exposes code graph tools (search_graph, trace_call_path, etc.)

## Configuration Files
- `.mcp.json`: MCP server registration (project-level)
- `~/.claude/settings.json`: Global Claude Code settings (hooks, statusline, MCP)
- `.claude/settings.local.json`: Per-project allowed tools
