---
phase: "03"
plan: "03"
title: "Write cmm-sentinel-writer.sh"
wave: 1
depends_on: []
must_haves:
  - PostToolUse:mcp__codebase-memory-mcp__index_repository hook
  - Writes "ready" to sentinel file
  - Outputs confirmation message
  - Always exit 0
  - "#!/bin/bash shebang"
  - File header with purpose, install instructions, matcher
---

# Plan 03: Write cmm-sentinel-writer.sh

## Output File
`hooks/project/cmm-sentinel-writer.sh`

## Task 1: Create the hook script

Create `hooks/project/cmm-sentinel-writer.sh` with the following implementation:

### File Header
```bash
#!/bin/bash
# cmm-sentinel-writer.sh — PostToolUse:mcp__codebase-memory-mcp__index_repository hook
# Writes sentinel file to unblock the session gate after index_repository completes.
# Always exits 0.
#
# Install: cp hooks/project/cmm-sentinel-writer.sh .claude/hooks/ && chmod +x .claude/hooks/cmm-sentinel-writer.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__codebase-memory-mcp__index_repository", "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-sentinel-writer.sh"}] }] }
#
# Matcher: mcp__codebase-memory-mcp__index_repository
```

### Sentinel Write
Write the "ready" marker to the sentinel file:
```bash
SENTINEL="/tmp/cmm-session-ready-${PPID}"
echo "ready" > "$SENTINEL"
```

### Confirmation Message
Output an advisory message confirming the sentinel was written:
```bash
echo "CMM index ready. Session gate unlocked — all tools now available."
```

### Exit
Always `exit 0`.

### Permissions
File must be created with executable permission (chmod +x).

## Acceptance Criteria
- [ ] File exists at `hooks/project/cmm-sentinel-writer.sh`
- [ ] Shebang is `#!/bin/bash`
- [ ] Header includes purpose, install instructions, matcher
- [ ] Matcher is `mcp__codebase-memory-mcp__index_repository` (not wildcard)
- [ ] Writes "ready" to `/tmp/cmm-session-ready-${PPID}`
- [ ] Outputs confirmation message to stdout
- [ ] Always exits 0
