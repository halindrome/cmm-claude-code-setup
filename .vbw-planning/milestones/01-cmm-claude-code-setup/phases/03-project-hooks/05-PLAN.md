---
phase: "03"
plan: "05"
title: "Write track-cmm-calls.sh"
wave: 1
depends_on: []
must_haves:
  - PostToolUse:mcp__codebase-memory-mcp__* hook
  - Tracks call counts per CMM tool to JSON file
  - Atomic write via temp file + mv
  - Silent (no output)
  - Always exit 0 (fail silently)
  - "#!/bin/bash shebang"
  - File header with purpose, install instructions, matcher
---

# Plan 05: Write track-cmm-calls.sh

## Output File
`hooks/project/track-cmm-calls.sh`

## Task 1: Create the hook script

Create `hooks/project/track-cmm-calls.sh` with the following implementation:

### File Header
```bash
#!/bin/bash
# track-cmm-calls.sh — PostToolUse:mcp__codebase-memory-mcp__* hook (CMM call counter)
# Tracks call counts per CMM tool. Silent, never blocks, always exits 0.
#
# Install: cp hooks/project/track-cmm-calls.sh .claude/hooks/ && chmod +x .claude/hooks/track-cmm-calls.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__codebase-memory-mcp__*", "hooks": [{"type": "command", "command": "bash .claude/hooks/track-cmm-calls.sh"}] }] }
#
# Matcher: mcp__codebase-memory-mcp__* (all CMM tools)
```

### Input Parsing
Read JSON from stdin, extract `tool_name` using python3:
```bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
```
If TOOL is empty, exit 0 immediately.

### Counter File Path
```bash
COUNTER_DIR="$HOME/.cache/codebase-memory-mcp"
COUNTER_FILE="$COUNTER_DIR/_call-counts.json"
```

### Ensure Directory Exists
```bash
mkdir -p "$COUNTER_DIR"
```

### JSON Structure
The counter file uses this structure:
```json
{
  "total_calls": 87,
  "by_tool": {
    "mcp__codebase-memory-mcp__search_graph": 32,
    "mcp__codebase-memory-mcp__get_code_snippet": 19
  }
}
```

### Atomic Update with python3
Use python3 for the JSON read-modify-write (not jq — consistent with other hooks' input parsing convention). Write to a temp file and atomically rename:

```bash
TEMP=$(mktemp)
python3 -c "
import json, sys, os

tool = '$TOOL'
counter_file = '$COUNTER_FILE'

# Read existing data or start fresh
try:
    with open(counter_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {'total_calls': 0, 'by_tool': {}}

# Increment counters
data['total_calls'] = data.get('total_calls', 0) + 1
data['by_tool'][tool] = data.get('by_tool', {}).get(tool, 0) + 1

# Write to temp file
with open('$TEMP', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null && mv "$TEMP" "$COUNTER_FILE" 2>/dev/null || rm -f "$TEMP"
```

### Silent and Non-Blocking
- No output to stdout or stderr at any point
- If anything fails (python3 missing, write error, etc.), fail silently
- Always `exit 0`

### Exit
```bash
exit 0
```

### Permissions
File must be created with executable permission (chmod +x).

## Acceptance Criteria
- [ ] File exists at `hooks/project/track-cmm-calls.sh`
- [ ] Shebang is `#!/bin/bash`
- [ ] Header includes purpose, install instructions, matcher
- [ ] Matcher is `mcp__codebase-memory-mcp__*` (wildcard for all CMM tools)
- [ ] Reads `tool_name` from JSON stdin via python3
- [ ] Counter file is at `~/.cache/codebase-memory-mcp/_call-counts.json`
- [ ] Creates directory `~/.cache/codebase-memory-mcp/` if missing
- [ ] JSON structure has `total_calls` (number) and `by_tool` (object of tool_name→count)
- [ ] Uses atomic write: temp file + mv
- [ ] Cleans up temp file on failure (rm -f)
- [ ] Completely silent — no output to stdout or stderr
- [ ] Always exits 0 regardless of errors
