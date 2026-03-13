---
phase: "03"
plan: "01"
title: "Write cmm-session-start.sh"
wave: 1
depends_on: []
must_haves:
  - SessionStart hook deletes stale sentinel
  - Injects mandatory first-action prompt
  - Always exit 0
  - "#!/bin/bash shebang"
  - File header with purpose, install instructions, matcher
---

# Plan 01: Write cmm-session-start.sh

## Output File
`hooks/project/cmm-session-start.sh`

## Task 1: Create the hook script

Create `hooks/project/cmm-session-start.sh` with the following implementation:

### File Header
```bash
#!/bin/bash
# cmm-session-start.sh — SessionStart hook (CMM index enforcement)
# Deletes stale sentinel and injects mandatory first-action prompt.
# Always exits 0.
#
# Install: cp hooks/project/cmm-session-start.sh .claude/hooks/ && chmod +x .claude/hooks/cmm-session-start.sh
# Register in .claude/settings.json:
#   "hooks": { "SessionStart": [{ "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-session-start.sh"}] }] }
#
# Matcher: SessionStart (no matcher needed — fires on every session start)
```

### Sentinel Deletion
Delete the stale sentinel file to force a fresh index check on every new session:
```bash
SENTINEL="/tmp/cmm-session-ready-${PPID}"
rm -f "$SENTINEL"
```

### Mandatory First-Action Prompt
Output the prompt injection text. This text becomes a system message injected before the session. Use a heredoc with single-quoted delimiter to prevent variable expansion:

```bash
cat <<'PROMPT'
**MANDATORY FIRST ACTION — Do this before responding to the user:**

1. Run `index_status` to check if the codebase-memory-mcp graph is current.
2. If the index is stale, missing, or has never been built, run `index_repository` to refresh it.
3. Only after the index is confirmed current, proceed with the user's request.

Do NOT skip this step. The session gate will block all other tools until indexing is complete.
PROMPT
```

### Exit
Always `exit 0`. SessionStart hooks must never block.

### Permissions
File must be created with executable permission (chmod +x).

## Acceptance Criteria
- [ ] File exists at `hooks/project/cmm-session-start.sh`
- [ ] Shebang is `#!/bin/bash`
- [ ] Header includes purpose, install instructions, matcher info
- [ ] Deletes sentinel at `/tmp/cmm-session-ready-${PPID}`
- [ ] Outputs mandatory first-action prompt mentioning `index_status` and `index_repository`
- [ ] Prompt mentions session gate blocking until indexing is complete
- [ ] Always exits 0
