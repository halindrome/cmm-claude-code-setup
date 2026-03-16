#!/bin/bash
# agent-cmm-gate.sh — PreToolUse:Agent hook (ensures agents use CMM tools)
# BLOCKING: exits 2 if agent prompt lacks CMM keywords, 0 if present or exempt.
#
# Install: cp hooks/project/agent-cmm-gate.sh .claude/hooks/ && chmod +x .claude/hooks/agent-cmm-gate.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Agent", "hooks": [{"type": "command", "command": "bash .claude/hooks/agent-cmm-gate.sh"}] }] }
# Matcher: PreToolUse:Agent

# --- Input Parsing ---
INPUT=$(cat)
SUBAGENT_TYPE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('subagent_type',''))" 2>/dev/null || echo "")
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('prompt',''))" 2>/dev/null || echo "")

# --- Subagent Type Exemption ---
# Built-in Claude Code skills and non-coding agents are exempt from the keyword gate.
case "$SUBAGENT_TYPE" in
  claude-code-guide|statusline-setup|Explore|Plan|vbw:*)
    echo "CMM note: agent type '$SUBAGENT_TYPE' exempted from keyword gate."
    exit 0
    ;;
esac

# --- Explicit bypass marker ---
# Add "# cmm-exempt" anywhere in the prompt to skip the gate for non-code tasks.
if echo "$PROMPT" | grep -q "cmm-exempt"; then
  exit 0
fi

# --- Non-code prompt heuristic ---
# Short prompts (<300 chars) with no code-exploration signals are exempt.
# Code signals: file/function/class/method/repo/codebase/import/hook/script/grep/refactor/debug
PROMPT_LEN=${#PROMPT}
CODE_SIGNALS="file|function|class|method|repo|codebase|import|hook|script|grep|refactor|debug|source|endpoint|schema|module|package|implement"
if [ "$PROMPT_LEN" -lt 300 ] && ! echo "$PROMPT" | grep -qiE "$CODE_SIGNALS"; then
  exit 0
fi

# --- Keyword Check: CMM tool function names ---
KEYWORDS="search_graph|trace_call_path|get_code_snippet|index_repository|detect_changes|get_architecture|query_graph|ctx_execute|ctx_search|ctx_index|ctx_fetch_and_index|ctx_batch_execute"
if echo "$PROMPT" | grep -qiE "$KEYWORDS"; then
  exit 0
fi

# --- Keywords missing: block and provide full instructions ---
cat >&2 <<'BLOCKED'
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

If using Context Mode MCP: ctx_execute, ctx_search, ctx_index, ctx_fetch_and_index
also satisfy this requirement.

--- End of copy-paste instructions ---
BLOCKED
exit 2
