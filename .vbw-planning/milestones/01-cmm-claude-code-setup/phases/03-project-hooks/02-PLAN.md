---
phase: "03"
plan: "02"
title: "Write cmm-session-gate.sh"
wave: 1
depends_on: []
must_haves:
  - PreToolUse:* hook blocks ALL tools until sentinel exists
  - Exceptions for index_repository, index_status, ToolSearch
  - Exit 2 with explanatory blocking message when sentinel missing
  - Exit 0 when sentinel exists or tool is exempt
  - "#!/bin/bash shebang"
  - File header with purpose, install instructions, matcher
---

# Plan 02: Write cmm-session-gate.sh

## Output File
`hooks/project/cmm-session-gate.sh`

## Task 1: Create the hook script

Create `hooks/project/cmm-session-gate.sh` with the following implementation:

### File Header
```bash
#!/bin/bash
# cmm-session-gate.sh — PreToolUse:* hook (blocks tools until CMM index is ready)
# BLOCKING: exits 2 if sentinel missing, 0 if present or tool is exempt.
#
# Install: cp hooks/project/cmm-session-gate.sh .claude/hooks/ && chmod +x .claude/hooks/cmm-session-gate.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "*", "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-session-gate.sh"}] }] }
#
# Matcher: * (all tools)
```

### Sentinel Path
```bash
SENTINEL="/tmp/cmm-session-ready-${PPID}"
```

### Input Parsing
Read JSON from stdin, extract `tool_name` using python3:
```bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
```

### Allow-List Check (before sentinel check)
Always allow these tools through regardless of sentinel state. Use a `case` statement:
```bash
case "$TOOL" in
  mcp__codebase-memory-mcp__index_repository|mcp__codebase-memory-mcp__index_status) exit 0 ;;
  ToolSearch) exit 0 ;;
esac
```

### Sentinel Check
If sentinel file exists, allow all tools:
```bash
[ -f "$SENTINEL" ] && exit 0
```

### Blocking Message
If sentinel is missing and tool is not exempt, output a blocking message and exit 2:
```bash
cat <<'BLOCK'
BLOCKED: codebase-memory-mcp index not ready.

Before using any tools, you must:
1. Run index_status to check the current index state.
2. Run index_repository to build/refresh the index.

The session gate will unblock automatically after index_repository completes.
BLOCK
exit 2
```

### Permissions
File must be created with executable permission (chmod +x).

## Acceptance Criteria
- [ ] File exists at `hooks/project/cmm-session-gate.sh`
- [ ] Shebang is `#!/bin/bash`
- [ ] Header includes purpose, install instructions, matcher
- [ ] Reads `tool_name` from JSON stdin via python3
- [ ] Always allows `mcp__codebase-memory-mcp__index_repository` through
- [ ] Always allows `mcp__codebase-memory-mcp__index_status` through
- [ ] Always allows `ToolSearch` through
- [ ] Exits 0 when sentinel `/tmp/cmm-session-ready-${PPID}` exists
- [ ] Exits 2 with explanatory message when sentinel missing and tool not exempt
- [ ] Blocking message tells user to run index_status then index_repository
