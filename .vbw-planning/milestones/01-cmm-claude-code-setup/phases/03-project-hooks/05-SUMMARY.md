---
phase: "03"
plan: "05"
title: "Write track-cmm-calls.sh"
status: complete
completed_at: "2026-03-12"
commits: []
files_modified:
  - hooks/project/track-cmm-calls.sh
deviations: []
---

## What Was Built
track-cmm-calls.sh PostToolUse hook that silently tracks CMM tool call counts to ~/.cache/codebase-memory-mcp/_call-counts.json. Uses Python for atomic JSON read-modify-write. Always exit 0, never output.

## Files Modified
- `hooks/project/track-cmm-calls.sh` — new PostToolUse hook for CMM call counting

## Tasks Completed
- [x] Write hooks/project/track-cmm-calls.sh with atomic JSON write and silent operation
