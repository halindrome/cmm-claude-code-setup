---
phase: "03"
plan: "04"
title: "Write agent-cmm-gate.sh"
wave: 1
depends_on: []
must_haves:
  - PreToolUse:Agent hook checks agent prompt for CMM keywords
  - Exempts claude-code-guide subagent_type
  - Exit 0 if keywords found or subagent exempt
  - Exit 2 with full copy-paste MCP instructions if keywords missing
  - "#!/bin/bash shebang"
  - File header with purpose, install instructions, matcher
---

# Plan 04: Write agent-cmm-gate.sh

## Output File
`hooks/project/agent-cmm-gate.sh`

## Task 1: Create the hook script

Create `hooks/project/agent-cmm-gate.sh` with the following implementation:

### File Header
```bash
#!/bin/bash
# agent-cmm-gate.sh — PreToolUse:Agent hook (ensures agents use CMM tools)
# BLOCKING: exits 2 if agent prompt lacks CMM keywords, 0 if present or exempt.
#
# Install: cp hooks/project/agent-cmm-gate.sh .claude/hooks/ && chmod +x .claude/hooks/agent-cmm-gate.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Agent", "hooks": [{"type": "command", "command": "bash .claude/hooks/agent-cmm-gate.sh"}] }] }
#
# Matcher: Agent
```

### Input Parsing
Read JSON from stdin, extract `prompt` and `subagent_type` using python3:
```bash
INPUT=$(cat)
SUBAGENT_TYPE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('subagent_type',''))" 2>/dev/null)
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null)
```

### Subagent Type Exemption
If `subagent_type` is `claude-code-guide`, allow through without keyword check:
```bash
[ "$SUBAGENT_TYPE" = "claude-code-guide" ] && exit 0
```

### Keyword Check
Check the prompt for CMM-related keywords using grep with extended regex. The keywords are the key CMM tool function names:
```bash
KEYWORDS="search_graph|trace_call_path|get_code_snippet|index_repository|detect_changes|get_architecture|query_graph"
if echo "$PROMPT" | grep -qiE "$KEYWORDS"; then
  exit 0
fi
```

### Blocking Message with Full MCP Instructions
If no keywords found, output the full copy-paste instructions and exit 2. This message must contain enough detail for the user to add CMM tool usage to the agent prompt:

```bash
cat <<'BLOCK'
BLOCKED: Agent prompt does not reference codebase-memory-mcp tools.

Agents MUST use the codebase-memory-mcp (CMM) graph tools for code exploration
instead of reading files directly. Add these instructions to your agent prompt:

--- Copy-paste the following into your agent prompt ---

Use codebase-memory-mcp (CMM) tools for code exploration. Available tools:

1. search_graph — Find functions/classes by name pattern, filter by degree
   Example: search_graph(name_pattern=".*Handler.*", label="Function")

2. get_code_snippet — Retrieve source code for a function/class by name
   Example: get_code_snippet(qualified_name="main.HandleRequest")

3. trace_call_path — Trace who calls a function and what it calls
   Example: trace_call_path(function_name="ProcessOrder", direction="both")

4. get_architecture — Get codebase architecture overview
   Example: get_architecture(aspects=["packages", "hotspots"])

5. query_graph — Execute Cypher-like graph queries
   Example: query_graph(query="MATCH (f:Function)-[:CALLS]->(g:Function) WHERE f.name = 'main' RETURN g.name LIMIT 20")

6. detect_changes — Map uncommitted changes to affected graph symbols
   Example: detect_changes(scope="all")

7. index_repository — Index or refresh the code graph
   Example: index_repository()

Workflow: search_graph → trace_call_path → get_code_snippet
Prefer these over Read/Grep for understanding code structure and relationships.

--- End of copy-paste instructions ---
BLOCK
exit 2
```

### Permissions
File must be created with executable permission (chmod +x).

## Acceptance Criteria
- [ ] File exists at `hooks/project/agent-cmm-gate.sh`
- [ ] Shebang is `#!/bin/bash`
- [ ] Header includes purpose, install instructions, matcher
- [ ] Reads `prompt` and `subagent_type` from JSON stdin via python3
- [ ] Exempts `claude-code-guide` subagent_type (exits 0 without keyword check)
- [ ] Checks prompt for all 7 keywords: search_graph, trace_call_path, get_code_snippet, index_repository, detect_changes, get_architecture, query_graph
- [ ] Exits 0 if any keyword found (case-insensitive)
- [ ] Exits 2 with full copy-paste MCP instructions if no keywords found
- [ ] Blocking message includes all 7 CMM tools with usage examples
- [ ] Blocking message includes recommended workflow pattern
