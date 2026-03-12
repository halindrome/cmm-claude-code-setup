---
phase: "04"
plan: "02"
title: "Write rules/project-settings-example.json"
status: complete
completed_at: "2026-03-12"
commits:
  - "feat(rules): add project-settings-example.json hook registration template"
files_modified:
  - rules/project-settings-example.json
deviations: []
---

## What Was Built
Complete JSON template for merging into a project's `.claude/settings.json`. Registers all 5 project-level hooks with correct matchers and relative `.claude/hooks/` paths.

## Tasks Completed
- [x] Create rules/project-settings-example.json with all 5 project hooks
- [x] Validate JSON syntax (python3 -m json.tool)

## Files Modified
- `rules/project-settings-example.json` — hook registration template (SessionStart, PreToolUse x2, PostToolUse x2)
