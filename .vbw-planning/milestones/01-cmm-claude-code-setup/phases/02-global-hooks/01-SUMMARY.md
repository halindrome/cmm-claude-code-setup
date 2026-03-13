---
phase: 02
plan: 01
title: "Write cmm-nudge.sh global hook"
status: complete
completed: 2026-03-12
tasks_completed: 1
tasks_total: 1
commit_hashes:
  - no-git
deviations:
  - "none"
---

Created non-blocking PreToolUse:Read hook that nudges users toward CMM graph tools for codebase exploration.

## What Was Built

- `hooks/global/cmm-nudge.sh` — advisory hook that prints a tip suggesting search_graph, get_code_snippet, and trace_call_path when Read is used on source files

## Files Modified

- `hooks/global/cmm-nudge.sh` -- created: non-blocking PreToolUse:Read hook with CMM graph tool advisory

## Deviations

None. All acceptance criteria met:
- Always exits 0 (non-blocking advisory)
- Header includes purpose, install instructions, matcher info
- Shebang is #!/bin/bash
- Extension list covers CMM's 64 supported languages
- Meta files (CLAUDE.md, MEMORY.md, etc.) excluded
- Planning paths (.vbw-planning/, .claude/, .git/) excluded
- Small files (<50 lines) excluded
- Advisory message mentions search_graph, get_code_snippet, trace_call_path
