# Phase 04 Research: Rules + Config Templates

## Findings

### global-claude-md.md

**Format:** CLAUDE.md-ready section for appending to `~/.claude/CLAUDE.md`.

**Structure:**
1. Header: `## Code Knowledge Graph — codebase-memory-mcp (MANDATORY when available)`
2. Intro emphasizing PRIMARY tool status
3. **Tool Reference** — one rule per tool (9 tools + workflow patterns)
4. **When Read is correct** — explicit exceptions
5. **Workflow patterns** — orientation, call path, pre-commit

**Tool coverage (all 14, but rules for the 9 code-nav tools):**
- `get_architecture`: Use for orientation; language breakdown, hotspots, entry points, routes, cross-service boundaries
- `search_graph`: Find functions/classes by name pattern (regex) — NEVER grep for definitions
- `get_code_snippet`: Retrieve individual function/class with metadata; avoids reading entire files
- `trace_call_path`: BFS traversal of call chains; essential before refactoring
- `search_code`: Text search for string literals, error messages, TODOs — grep alternative
- `query_graph`: Cypher-like queries for complex relationship patterns, edge properties
- `detect_changes`: Map git diffs to affected symbols + blast radius; run before commits
- `index_repository`: Run at session start and after batch edits
- `manage_adr`: Maintain Architecture Decision Records (6 sections, max 8000 chars)

**When Read is correct (exceptions):**
- Non-code files (JSON, YAML, config, HTML templates)
- Full file context needed (imports, globals, module-level flow)
- Very small files (<50 lines)
- Files not yet indexed
- Editing 6+ functions in same file (batch edit cheaper)

**Tone:** Imperative (ALWAYS/NEVER). Tool names in backticks. Include workflow patterns.

---

### project-settings-example.json

**Format:** Complete JSON for merging into `.claude/settings.json` — all 7 project hooks.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-session-start.sh"}]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-session-gate.sh"}]
      },
      {
        "matcher": "Agent",
        "hooks": [{"type": "command", "command": "bash .claude/hooks/agent-cmm-gate.sh"}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__codebase-memory-mcp__index_repository",
        "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-sentinel-writer.sh"}]
      },
      {
        "hooks": [{"type": "command", "command": "bash .claude/hooks/track-cmm-calls.sh"}]
      }
    ]
  }
}
```

**Key patterns:**
- SessionStart: no matcher field
- PreToolUse `*`: cmm-session-gate.sh (blocks until sentinel)
- PreToolUse `Agent`: agent-cmm-gate.sh (blocks without CMM instructions)
- PostToolUse specific matcher: cmm-sentinel-writer.sh
- PostToolUse no matcher: track-cmm-calls.sh (fires on ALL PostToolUse)
- All paths: relative `.claude/hooks/` (project-local)

---

### mcp-example.json

**Format:** Minimal JSON for project root `.mcp.json`.

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

**Notes:**
- Uses `codebase-memory-mcp` command (assumes binary on PATH from `codebase-memory-mcp install`)
- Single server (unlike jmunch's two servers)
- `type: stdio` for standard I/O communication
- No absolute path needed (install script handles PATH)

---

### allowed-tools.txt

**Format:** One tool name per line. All 14 CMM tools.

**Complete list:**
```
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

**Usage:** Users convert to JSON array in `.claude/settings.local.json` under `"allowedTools"`.

---

## Relevant Patterns

### Global vs Project Hook Paths
- **Global** (`~/.claude/settings.json`): `"command": "bash \"$HOME/.claude/hooks/cmm-nudge.sh\""` (absolute)
- **Project** (`.claude/settings.json`): `"command": "bash .claude/hooks/cmm-session-gate.sh"` (relative)

### Multiple Matchers
- Multiple PreToolUse matchers are SEPARATE array entries
- PostToolUse without matcher fires on ALL PostToolUse events

### Global Settings (README already shows this)
```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Read", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/cmm-nudge.sh\""}]}
    ],
    "PostToolUse": [
      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/reindex-after-edit.sh\""}]}
    ]
  }
}
```

---

## Risks

1. **Binary path variability**: mcp-example.json assumes PATH; document `codebase-memory-mcp install` prerequisite
2. **settings.json merging**: Users must merge (not replace) with existing hooks — note this clearly
3. **allowed-tools.txt format**: Plain text, not JSON — include comment showing JSON conversion
4. **global-claude-md.md length**: Keep under 80 lines to avoid truncation in CLAUDE.md

---

## Recommendations

1. **global-claude-md.md**: Start with `## codebase-memory-mcp — Code Navigation (MANDATORY)`, imperative rules, tool reference, exceptions
2. **project-settings-example.json**: Include JSON comment at top (via README note, since JSON has no comments) explaining merge requirement
3. **mcp-example.json**: Add prerequisite note as a comment in docs (not in JSON itself)
4. **allowed-tools.txt**: Include header comment with JSON format example
5. **File placement per README**: All 4 files go in `rules/` directory

### Enforcement Hierarchy Summary
```
~/.claude/CLAUDE.md         ← global-claude-md.md content
~/.claude/settings.json     ← global hooks (nudge + reindex)
.claude/settings.json       ← project-settings-example.json content
.mcp.json                   ← mcp-example.json content
.claude/settings.local.json ← allowed-tools.txt content (as JSON array)
```
