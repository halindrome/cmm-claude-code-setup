---
phase: 05
plan: 01
status: complete
files_created:
  - setup.sh
commits: []
deviations: []
---

# Summary: setup.sh — automated hook installer

## What Was Built
setup.sh at project root (~200 lines). Complete bash installer with:
- CLI flags: --global, --project, --all, --force, --dry-run
- Interactive prompt when no flags provided
- python3-based JSON deep-merge for settings.json (no jq dependency)
- Atomic backup + write for settings.json
- JSON validation after every merge
- chmod +x on all installed hooks
- Warns if codebase-memory-mcp not on PATH

## Files Modified
- setup.sh (created)

## Verification
- bash -n syntax check passed
- --dry-run --global output confirmed correct
