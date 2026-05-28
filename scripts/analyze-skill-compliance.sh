#!/bin/bash
# Analyze Claude Code subagent JSONL transcripts for skill activation compliance
# Usage: ./scripts/analyze-skill-compliance.sh [project-dir]
# Default project-dir: $CLAUDE_CONFIG_DIR/projects (falls back to ~/.claude/projects)
# Exit: 0 always (reporting-only, no enforcement)
# Supports both the flat fixture format and the real Claude Code nested JSONL format.

set -euo pipefail

# --- Resolve search directory ---
if [ $# -ge 1 ]; then
  SEARCH_DIR="$1"
else
  CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
  if [ -z "$CONFIG_DIR" ]; then
    for candidate in "$HOME/.config/claude-code" "$HOME/.claude"; do
      if [ -d "$candidate" ]; then
        CONFIG_DIR="$candidate"
        break
      fi
    done
  fi
  SEARCH_DIR="${CONFIG_DIR}/projects"
fi

if [ ! -d "$SEARCH_DIR" ]; then
  echo "No project directory found at: $SEARCH_DIR"
  echo "Usage: $0 [project-dir]"
  exit 0
fi

# --- Discover JSONL files ---
JSONL_FILES=()
while IFS= read -r -d '' f; do
  JSONL_FILES+=("$f")
done < <(find "$SEARCH_DIR" -name "*.jsonl" -print0 2>/dev/null)

if [ ${#JSONL_FILES[@]} -eq 0 ]; then
  echo "No JSONL transcript files found under: $SEARCH_DIR"
  exit 0
fi

# --- Per-agent analysis ---
TOTAL_AGENTS=0
TOTAL_CMM_ACTIVATIONS=0
TOTAL_CTX_ACTIVATIONS=0
TOTAL_CTX_SEARCH=0
TOTAL_CMM_TOOLS=0
TOTAL_BASH=0
TOTAL_READ=0

echo "============================================================"
echo "Skill Compliance Report"
echo "Search dir: $SEARCH_DIR"
echo "============================================================"
printf "%-40s %6s %6s %6s %6s %6s %6s\n" "Agent file" "cmm" "ctx" "srch" "cmm-t" "bash" "read"
echo "------------------------------------------------------------"

for f in "${JSONL_FILES[@]}"; do
  AGENT_NAME=$(basename "$f" .jsonl)
  SHORT="${AGENT_NAME:0:38}"

  # Parse metrics from JSONL using python3
  # Handles two formats:
  # 1. Flat: {"type":"tool_use","name":"Skill","input":{...}}  (fixtures)
  # 2. Nested: {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{...}}]}}
  METRICS=$(python3 -c "
import sys, json

cmm_rules = 0
ctx_rules = 0
ctx_search = 0
cmm_tools = 0
bash_calls = 0
read_calls = 0

CMM_TOOLS = {'search_graph', 'get_code_snippet', 'trace_path', 'query_graph', 'get_architecture', 'search_code'}

def process_tool(name, inp):
    global cmm_rules, ctx_rules, ctx_search, cmm_tools, bash_calls, read_calls
    if name == 'Skill':
        skill = inp.get('skill', '') if isinstance(inp, dict) else ''
        if skill == 'cmm-rules':
            cmm_rules += 1
        elif skill == 'ctx-rules':
            ctx_rules += 1
    elif name == 'Bash':
        bash_calls += 1
    elif name == 'Read':
        read_calls += 1
    elif 'ctx_search' in name or name.endswith('ctx_search'):
        ctx_search += 1
    elif 'codebase-memory-mcp' in name:
        tool_short = name.split('__')[-1] if '__' in name else name
        if tool_short in CMM_TOOLS:
            cmm_tools += 1

with open(sys.argv[1]) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        t = obj.get('type', '')
        # Format 1: flat tool_use record
        if t in ('tool_use', 'tool_call'):
            process_tool(obj.get('name', ''), obj.get('input', obj.get('tool_input', {})))
        # Format 2: nested inside assistant/user message.content[]
        elif t in ('assistant', 'user'):
            msg = obj.get('message', {})
            if isinstance(msg, dict):
                content = msg.get('content', [])
                if isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get('type') == 'tool_use':
                            process_tool(item.get('name', ''), item.get('input', {}))
        # Format 3: direct message object (no outer wrapper)
        elif t == 'message':
            content = obj.get('content', [])
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get('type') == 'tool_use':
                        process_tool(item.get('name', ''), item.get('input', {}))

print(cmm_rules, ctx_rules, ctx_search, cmm_tools, bash_calls, read_calls)
" "$f" 2>/dev/null) || METRICS="0 0 0 0 0 0"

  read CMM CTX SRCH CMMT BASH READ <<< "$METRICS"
  printf "%-40s %6d %6d %6d %6d %6d %6d\n" "$SHORT" "$CMM" "$CTX" "$SRCH" "$CMMT" "$BASH" "$READ"

  TOTAL_AGENTS=$((TOTAL_AGENTS + 1))
  TOTAL_CMM_ACTIVATIONS=$((TOTAL_CMM_ACTIVATIONS + CMM))
  TOTAL_CTX_ACTIVATIONS=$((TOTAL_CTX_ACTIVATIONS + CTX))
  TOTAL_CTX_SEARCH=$((TOTAL_CTX_SEARCH + SRCH))
  TOTAL_CMM_TOOLS=$((TOTAL_CMM_TOOLS + CMMT))
  TOTAL_BASH=$((TOTAL_BASH + BASH))
  TOTAL_READ=$((TOTAL_READ + READ))
done

echo "============================================================"
echo "Totals ($TOTAL_AGENTS agents):"
echo "  Skill('cmm-rules') activations : $TOTAL_CMM_ACTIVATIONS / $TOTAL_AGENTS agents"
echo "  Skill('ctx-rules') activations : $TOTAL_CTX_ACTIVATIONS / $TOTAL_AGENTS agents"
if [ "$TOTAL_AGENTS" -gt 0 ]; then
  CMM_RATE=$(python3 -c "print(f'{100*$TOTAL_CMM_ACTIVATIONS/$TOTAL_AGENTS:.0f}%')" 2>/dev/null || echo "N/A")
  CTX_RATE=$(python3 -c "print(f'{100*$TOTAL_CTX_ACTIVATIONS/$TOTAL_AGENTS:.0f}%')" 2>/dev/null || echo "N/A")
  echo "  cmm-rules activation rate      : $CMM_RATE"
  echo "  ctx-rules activation rate      : $CTX_RATE"
fi
echo "  ctx_search calls (total)        : $TOTAL_CTX_SEARCH"
echo "  CMM explore tool calls (total)  : $TOTAL_CMM_TOOLS"
if [ "$TOTAL_CMM_TOOLS" -gt 0 ]; then
  RATIO=$(python3 -c "print(f'{$TOTAL_BASH/$TOTAL_CMM_TOOLS:.1f}:1')" 2>/dev/null || echo "N/A")
  echo "  Bash:CMM ratio                  : $RATIO (Bash=$TOTAL_BASH CMM=$TOTAL_CMM_TOOLS)"
else
  echo "  Bash:CMM ratio                  : $TOTAL_BASH:0 (no CMM calls)"
fi
echo "  Read calls (total)              : $TOTAL_READ"
echo "============================================================"

exit 0
