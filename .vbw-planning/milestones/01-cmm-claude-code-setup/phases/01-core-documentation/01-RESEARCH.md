# Phase 01 Research: Core Documentation

## Findings

### jmunch README Structure (to mirror)
Section order in jmunch README.md:
1. Title + hook/rule/statusline overview
2. Attribution paragraph (credit + GitHub link) — front and center, line 3
3. "What jCodeMunch & jDocMunch Do" — explanation + enforcement layers table
4. Quick Start — 6-step bash block
5. Repository Structure — directory tree
6. How Enforcement Works — session lifecycle diagram
7. Token savings tracking (CMM equivalent: call counting)
8. Statusline — versions + registration example
9. Subagent Instructions Template — copy-paste block
10. Requirements — tools/deps
11. Credits
12. License

### Unique Content in codebase-memory-setup-guide.md (migrate to docs/)
Content NOT in jmunch structure that should be kept:
- Architecture overview tools: get_architecture, get_graph_schema, manage_adr
- Advanced queries: Cypher-like syntax, cross-service HTTP/async edge filtering
- Complete tool reference table (14 tools by category)
- Recommended workflows: first-time exploration, finding functions, pre-commit impact, dead code detection
- Data flow summary
- Troubleshooting section
- Incremental reindex details (content hashing, auto-sync background polling)

### CMM Installation Method (CRITICAL — NOT npm)
CMM is a **single Go binary**:
1. Binary download from GitHub releases: `tar xzf codebase-memory-mcp-*.tar.gz` + move to PATH
2. One-command install: `codebase-memory-mcp install` (auto-detects Claude Code, Cursor, etc.)
3. Self-update: `codebase-memory-mcp update`
No Docker, no Node.js, no npm. Different from jCodeMunch (Python/uv).

### The 14 CMM Tool Names
index_repository, index_status, list_projects, delete_project, get_architecture, search_graph, search_code, get_code_snippet, trace_call_path, query_graph, get_graph_schema, detect_changes, manage_adr, ingest_traces

## Relevant Patterns

### Attribution Pattern (from jmunch)
- Attribution is front-loaded: first non-title content
- "Credit where it's due" paragraph with bolded names + GitHub links
- Repo disclaimer: "This repo does not contain those MCP servers — it provides a companion enforcement and tracking layer"
- For CMM: cite Shachar Bard (NOT jgravelle) with link to https://github.com/shacharbard

### Enforcement Stack Table (from jmunch)
| Layer | What | Effect |
- CLAUDE.md rules | Instructions | Tells Claude when to use tools
- PreToolUse nudge hooks | Non-blocking | Reminds when Read is used
- Session gate | Blocking | Blocks ALL tools until index refreshed
- Agent spawn gate | Blocking | Blocks agents without MCP instructions
- PostToolUse trackers | Passive | Tracks call counts (CMM: not token savings)
- Statusline | Display | Shows CMM stats in status bar

### Session Lifecycle Diagram (mirror jmunch's ASCII format)

## Risks

1. **CMM binary install vs npm**: existing guide assumes npm. README must clarify binary download.
2. **Attribution to wrong person**: Shachar Bard (jmunch) ≠ J. Gravelle (jCodeMunch). Must cite Shachar Bard.
3. **1 MCP server vs 2**: CMM is single .mcpServers entry with 14 tools; jmunch has two separate servers.
4. **No tokens_saved field**: CMM tracks call counts, not token savings. Enforcement layer table differs.
5. **Existing guide predates hooks**: SessionStart hook example, session gate, agent gate sections all need updating.

## Recommendations

### README.md Section Structure
1. Title + lead sentence (mirror jmunch opening)
2. Attribution paragraph — Shachar Bard, link to shacharbard/jmunch-claude-code-setup (front and center)
3. Core value / what CMM + enforcement does
4. Enforcement layers table (mirror jmunch table format)
5. Quick Start — binary download + codebase-memory-mcp install + first use
6. Repository Structure — hooks/global, hooks/project, rules/, docs/, setup.sh
7. How Enforcement Works — session lifecycle diagram (CMM single-sentinel version)
8. Call Tracking (track-cmm-calls.sh — counts per tool, not token savings)
9. Statusline — README example only (code snippet, no script file)
10. Subagent Instructions Template — copy-paste block with CMM tool rules
11. Requirements — Bash, jq, python3, git (no npm)
12. Credits — Shachar Bard (inspiration) + DeusData (CMM creators)
13. License

### docs/setup-guide.md
Migrate existing codebase-memory-setup-guide.md but UPDATE:
- Step 1: binary download (not npm install -g)
- Step 6: add enforcement hooks section (session gate, agent gate, call tracker)
- Session lifecycle: add project-level hook details
KEEP as-is: tool reference tables, workflows, troubleshooting, data flow summary
