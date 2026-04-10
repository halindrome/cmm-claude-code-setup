---
phase: 43
round: 02
title: "Close enforcer cold-start gap and add Grep tool CMM nudge"
type: remediation
status: in-progress
tasks_completed: 2
tasks_total: 4
commit_hashes:
  - 00d6322
files_modified:
  - hooks/project/cmm-session-start.sh
  - hooks/global/cmm-grep-nudge.sh
deviations: []
---

Round 02 remediation in progress. Task 1 complete: sentinel ordering documented.

## Task 1: Pre-write Context Mode sentinel for existing installations

### What Was Built
- Verified existing sentinel pre-write logic at lines 84-89 already handles the `.claude/context-mode.db` case correctly
- Added comment block explaining the SessionStart ordering guarantee: SessionStart hooks run synchronously before any PreToolUse hooks fire, so the sentinel is guaranteed to exist before ctx-execute-enforcer.sh checks it
- Confirmed sentinel path `/tmp/context-mode-ready-${PROJECT_HASH}` matches between cmm-session-start.sh and ctx-execute-enforcer.sh

### Files Modified
- `hooks/project/cmm-session-start.sh` -- updated: added ordering guarantee comment documenting why the delete-then-recreate sentinel pattern is safe

### Deviations
None

## Task 2: Create cmm-grep-nudge.sh hook

### What Was Built
- Created `hooks/global/cmm-grep-nudge.sh` — PreToolUse:Grep hook that blocks Grep on code file extensions when CMM is available, redirecting to search_graph/search_code
- Mirrors cmm-nudge.sh pattern: same extension list, same CMM availability check, same exempt paths
- Checks three input fields: `glob` (code extension pattern), `type` (ripgrep type name), `path` (specific code file when no glob/type set)
- Includes block counter integration via track-hook-blocks.sh

### Files Modified
- `hooks/global/cmm-grep-nudge.sh` -- added: new PreToolUse:Grep hook blocking code-targeted Grep when CMM is available

### Deviations
None
