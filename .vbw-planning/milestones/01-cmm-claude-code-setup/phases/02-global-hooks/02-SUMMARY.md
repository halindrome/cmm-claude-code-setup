---
phase: 02
plan: 02
title: "Write reindex-after-edit.sh global hook"
status: complete
completed: 2026-03-12
tasks_completed: 1
tasks_total: 1
commit_hashes:
  - no-git
deviations:
  - "none"
---

Created PostToolUse:Write|Edit hook that advises users to refresh the CMM index after source file edits, with 60s debounce and jq/python3 fallback.

## What Was Built

- `hooks/global/reindex-after-edit.sh` — non-blocking PostToolUse hook that reminds users to run `index_repository` after modifying CMM-indexed source files

## Files Modified

- `hooks/global/reindex-after-edit.sh` -- created: PostToolUse:Write|Edit hook with 60s debounce, jq+python3 fallback, 64-language extension check, path exclusions for .vbw-planning/.claude/.git

## Deviations

None. Implementation follows plan exactly.
