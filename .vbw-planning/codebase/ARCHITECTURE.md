# Architecture

## Overview
This project is a **documentation and configuration guide** for setting up `codebase-memory-mcp` in Claude Code projects. It contains a single markdown guide plus configuration templates/examples.

## Components

### codebase-memory-setup-guide.md
The primary deliverable — a step-by-step guide covering:
1. MCP server installation (`npm install -g codebase-memory-mcp`)
2. MCP server registration (project `.mcp.json` or global `claude mcp add`)
3. Tool permissions (`.claude/settings.local.json` allowedTools)
4. Auto-index SessionStart hook (prompt-type)
5. CLAUDE.md rules (when to use graph tools vs Read)
6. Enforcement hooks (PreToolUse nudge, PostToolUse reindex)
7. Tool reference (all MCP tools documented)
8. Recommended workflows (exploration, search, impact analysis, dead code)
9. Hook registry (complete table)
10. Data flow summary
11. Troubleshooting

## Patterns
- **Progressive setup**: Steps 1-5 are required; steps 6+ are optional enhancements
- **Dual enforcement**: CLAUDE.md rules (soft) + hooks (hard enforcement)
- **Debounced re-index**: 60s debounce on PostToolUse to avoid repeated indexing
