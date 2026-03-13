---
phase: "04-rules-config-templates"
verification: standard
verdict: PASS
checks_passed: 33
checks_total: 33
verified_at: "2026-03-12"
---

## Results

All 33 checks passed across all four rule/config template files. Every required tool rule, hook registration, JSON structure, and tool list entry is present and correct.

## Issues

None.

## Checks

### Must-Have Checks — global-claude-md.md (REQ-10)

| # | ID | Truth/Condition | Status | Evidence |
|---|----|-----------------|---------:|----------|
| 1 | MH-01 | Has `##` header (CLAUDE.md-ready section) | PASS | Line 3: `## codebase-memory-mcp — Code Navigation (MANDATORY)` |
| 2 | MH-02 | Instructions to append to ~/.claude/CLAUDE.md | PASS | Line 1: `> Add this section to your ~/.claude/CLAUDE.md file` |
| 3 | MH-03 | Rules for get_architecture (orientation, aspects parameter) | PASS | Lines 9, 30-31: ALWAYS run first, `aspects` parameter used in workflow |
| 4 | MH-04 | Rules for search_graph (NEVER grep for definitions) | PASS | Line 11: `NEVER use Grep to search for function/class definitions` |
| 5 | MH-05 | Rules for get_code_snippet (single function fetch) | PASS | Line 13: `NEVER read an entire file to get one function` |
| 6 | MH-06 | Rules for trace_call_path (before refactoring, direction parameter) | PASS | Line 15: `ALWAYS run before refactoring`, `direction='both'` |
| 7 | MH-07 | Rules for search_code (grep alternative) | PASS | Line 17: text search for literals, error messages, TODOs |
| 8 | MH-08 | Rules for query_graph (Cypher-like queries) | PASS | Line 19: `Cypher-like relationship queries`, LIMIT clause |
| 9 | MH-09 | Rules for detect_changes (pre-commit blast radius) | PASS | Line 21 and lines 41-44: pre-commit workflow with blast radius |
| 10 | MH-10 | Rules for index_repository (session start) | PASS | Line 23: `Run at session start and after batch edits` |
| 11 | MH-11 | Rules for manage_adr (6 sections) | PASS | Line 25: lists PURPOSE, STACK, ARCHITECTURE, PATTERNS, TRADEOFFS, PHILOSOPHY |
| 12 | MH-12 | Includes "When Read is Correct" exceptions section | PASS | Lines 46-54: `### When Read is Correct` section present |
| 13 | MH-13 | Exceptions include: non-code files, <50 lines, 6+ functions in same file | PASS | Lines 49, 51, 53: all three exception types present |
| 14 | MH-14 | Imperative tone (ALWAYS/NEVER/Use) | PASS | Multiple ALWAYS/NEVER throughout Tool Reference section |
| 15 | MH-15 | Under 80 lines | PASS | 54 lines total |

### Must-Have Checks — project-settings-example.json (REQ-11)

| # | ID | Truth/Condition | Status | Evidence |
|---|----|-----------------|---------:|----------|
| 16 | MH-16 | Valid JSON (parseable) | PASS | python3 json.load succeeded |
| 17 | MH-17 | Has "hooks" top-level key | PASS | Line 2: `"hooks": {` |
| 18 | MH-18 | SessionStart hook → cmm-session-start.sh | PASS | Lines 3-12: `bash .claude/hooks/cmm-session-start.sh` |
| 19 | MH-19 | PreToolUse `*` matcher → cmm-session-gate.sh | PASS | Lines 14-21: matcher `"*"`, cmm-session-gate.sh |
| 20 | MH-20 | PreToolUse `Agent` matcher → agent-cmm-gate.sh | PASS | Lines 22-30: matcher `"Agent"`, agent-cmm-gate.sh |
| 21 | MH-21 | PostToolUse `mcp__codebase-memory-mcp__index_repository` → cmm-sentinel-writer.sh | PASS | Lines 34-41: correct matcher and script |
| 22 | MH-22 | PostToolUse (no matcher) → track-cmm-calls.sh | PASS | Lines 43-49: no matcher entry with track-cmm-calls.sh |
| 23 | MH-23 | All commands use relative `.claude/hooks/` paths | PASS | All 5 commands use `bash .claude/hooks/<script>` pattern |

### Must-Have Checks — mcp-example.json (REQ-12)

| # | ID | Truth/Condition | Status | Evidence |
|---|----|-----------------|---------:|----------|
| 24 | MH-24 | Valid JSON (parseable) | PASS | python3 json.load succeeded |
| 25 | MH-25 | Has `mcpServers` key | PASS | Line 2: `"mcpServers": {` |
| 26 | MH-26 | Server named `codebase-memory-mcp` | PASS | Line 3: `"codebase-memory-mcp": {` |
| 27 | MH-27 | `command` is `"codebase-memory-mcp"` | PASS | Line 4: `"command": "codebase-memory-mcp"` |
| 28 | MH-28 | Has `args: []` and `type: "stdio"` | PASS | Lines 5-6: both fields present |

### Must-Have Checks — allowed-tools.txt (REQ-13)

| # | ID | Truth/Condition | Status | Evidence |
|---|----|-----------------|---------:|----------|
| 29 | MH-29 | Has all 14 CMM tools (mcp__codebase-memory-mcp__ prefix) | PASS | Lines 13-26: 14 tool entries |
| 30 | MH-30 | Includes index_repository, index_status, list_projects, delete_project | PASS | Lines 13-16: all four present |
| 31 | MH-31 | Includes get_architecture, get_graph_schema, search_graph, search_code, query_graph | PASS | Lines 17-21: all five present |
| 32 | MH-32 | Includes get_code_snippet, trace_call_path, detect_changes, manage_adr, ingest_traces | PASS | Lines 22-26: all five present |
| 33 | MH-33 | Has header comment showing JSON usage format | PASS | Lines 1-11: comment block with example JSON structure |

## Summary

Tier: Standard | Result: PASS | Passed: 33/33 | Failed: none
