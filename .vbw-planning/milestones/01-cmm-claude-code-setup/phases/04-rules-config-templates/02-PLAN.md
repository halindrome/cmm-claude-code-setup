---
phase: "04"
plan: "02"
title: "Write rules/project-settings-example.json"
wave: 1
depends_on: []
must_haves:
  - Valid JSON with all 5 project hooks
  - SessionStart hook (no matcher)
  - PreToolUse * and Agent matchers
  - PostToolUse with specific and no-matcher entries
  - Relative .claude/hooks/ paths
---

# Plan 02: Write `rules/project-settings-example.json`

## Output File
`rules/project-settings-example.json`

## Purpose
Complete JSON for merging into a project's `.claude/settings.json`. Registers all 5 project-level hooks with correct matchers and relative paths.

## Tasks

### Task 1: Create `rules/project-settings-example.json`

Write the following exact JSON content. This must be valid, parseable JSON (no comments inside the file).

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/cmm-session-start.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/cmm-session-gate.sh"
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/agent-cmm-gate.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__codebase-memory-mcp__index_repository",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/cmm-sentinel-writer.sh"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/track-cmm-calls.sh"
          }
        ]
      }
    ]
  }
}
```

### Key Design Points
- **SessionStart**: No `matcher` field — fires on every session start
- **PreToolUse `*`**: Wildcard matcher — `cmm-session-gate.sh` blocks ALL tools until sentinel exists
- **PreToolUse `Agent`**: Specific matcher — `agent-cmm-gate.sh` checks agent prompts for CMM instructions
- **PostToolUse with matcher**: `cmm-sentinel-writer.sh` fires only on `index_repository` completion
- **PostToolUse without matcher**: `track-cmm-calls.sh` fires on ALL PostToolUse events (no matcher field)
- **All paths are relative**: `.claude/hooks/` prefix (project-local, not absolute `$HOME` paths)
- **JSON must be valid**: No trailing commas, no comments. Pretty-printed with 2-space indent.

### Task 2: Validate JSON syntax

After writing, verify the file is valid JSON (e.g., parseable by `jq` or `python3 -m json.tool`).
