---
phase: 01
plan: 02
title: "Write docs/setup-guide.md comprehensive walkthrough"
status: complete
completed: 2026-03-12
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - no-git
deviations:
  - "Hook script names use cmm- prefix instead of codebase-memory- prefix for brevity (cmm-nudge.sh, cmm-session-start.sh, cmm-session-gate.sh, cmm-sentinel-writer.sh, agent-cmm-gate.sh, track-cmm-calls.sh)"
---

Comprehensive setup guide migrated from codebase-memory-setup-guide.md with updated binary install method, full enforcement hook documentation, and expanded troubleshooting.

## What Was Built

- Complete 7-step setup walkthrough covering binary install, MCP registration, tool allowlisting, CLAUDE.md rules, global hooks, project hooks, and auto-index lifecycle
- Tool reference table for all 14 CMM tools organized by category (Indexing & Status, Navigation & Search, Analysis & Operations)
- Session lifecycle data flow diagram showing gate/sentinel mechanism
- Recommended workflows section (first-time exploration, finding functions, pre-commit impact, dead code detection, cross-service HTTP links, ADR management)
- Troubleshooting section expanded with hook-specific issues (hooks not firing, sentinel issues, MCP connection problems)
- Complete hook registry table covering both global and project hooks with event/matcher/script/type/effect columns

## Files Modified

- `docs/setup-guide.md` -- created: Comprehensive setup guide with all 7 steps, tool reference, workflows, troubleshooting, and hook registry

## Deviations

- Hook script names use `cmm-` prefix (e.g., `cmm-nudge.sh`) instead of the longer `codebase-memory-` prefix used in the existing guide's `codebase-memory-nudge.sh`. This aligns with the project's naming convention (`cmm-claude-code-setup`) and keeps filenames concise.
