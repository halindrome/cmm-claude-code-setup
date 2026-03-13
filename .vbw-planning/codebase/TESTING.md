# Testing

## Current State
No automated tests. Documentation project.

## Manual Verification Steps (per guide)
- `codebase-memory-mcp --help` — confirms installation
- `index_status` in Claude Code — confirms MCP registration
- `index_repository` — confirms indexing works
- Hook verification: trigger Read on a .py file, confirm nudge fires

## Quality Checks
- Accuracy: code blocks should be copy-pasteable
- Completeness: all 14 MCP tools documented in Tool Reference
- Consistency: hook JSON matches exact Claude Code settings.json schema
