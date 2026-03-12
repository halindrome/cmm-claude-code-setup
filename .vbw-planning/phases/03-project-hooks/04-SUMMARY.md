---
phase: "03"
plan: "04"
title: "Write agent-cmm-gate.sh"
status: complete
completed_at: "2026-03-12"
commits:
  - 921c7df
files_modified:
  - hooks/project/agent-cmm-gate.sh
deviations: []
---

## What Was Built
agent-cmm-gate.sh PreToolUse:Agent hook that blocks subagent spawning if prompt lacks CMM keyword instructions, with full copy-paste instructions in blocking message. Exempts claude-code-guide subagent type.

## Files Modified
- `hooks/project/agent-cmm-gate.sh` — PreToolUse:Agent gate hook blocking subagents without CMM tool instructions

## Tasks Completed
- [x] Write hooks/project/agent-cmm-gate.sh with keyword detection and copy-paste MCP instructions
