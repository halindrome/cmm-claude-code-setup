---
phase: "03"
plan: "01"
title: "Write cmm-session-start.sh"
status: complete
completed_at: "2026-03-12"
commits:
  - "feat(hooks): add cmm-session-start.sh SessionStart hook"
files_modified:
  - hooks/project/cmm-session-start.sh
deviations: []
---

## What Was Built
cmm-session-start.sh SessionStart hook that deletes stale sentinel and injects mandatory index-refresh prompt.

## Tasks Completed
- [x] Write hooks/project/cmm-session-start.sh with sentinel deletion and prompt injection

## Files Modified
- `hooks/project/cmm-session-start.sh` — New SessionStart hook with sentinel deletion and mandatory index-refresh prompt injection
