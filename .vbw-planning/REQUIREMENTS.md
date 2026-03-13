# cmm-claude-code-setup Requirements

Defined: 2026-03-12 | Core value: Hook-based enforcement layer for codebase-memory-mcp + Claude Code

## v1 Requirements

### Documentation
- [ ] **REQ-01**: README.md with attribution to Shachar Bard (shacharbard) prominently at top, project overview, Quick Start, repo structure, statusline example, subagent instructions template, requirements
- [ ] **REQ-02**: docs/setup-guide.md comprehensive step-by-step walkthrough (migrates existing codebase-memory-setup-guide.md content, adds hook installation details)

### Global Hooks (install to ~/.claude/hooks/)
- [ ] **REQ-03**: `hooks/global/cmm-nudge.sh` — PreToolUse:Read, non-blocking reminder when Read is called on source files; extensible language list derived from CMM's supported types
- [ ] **REQ-04**: `hooks/global/reindex-after-edit.sh` — PostToolUse:Write|Edit, 60s debounce, prompts re-index after source file changes

### Project Hooks (install to .claude/hooks/)
- [ ] **REQ-05**: `hooks/project/cmm-session-start.sh` — SessionStart prompt injection; instructs Claude to run index_status and index_repository before doing anything else
- [ ] **REQ-06**: `hooks/project/cmm-session-gate.sh` — PreToolUse:*, hard blocking gate (exit 2); blocks all tools until index_repository completes; allows CMM tools through to create the sentinel
- [ ] **REQ-07**: `hooks/project/cmm-sentinel-writer.sh` — PostToolUse:mcp__codebase-memory-mcp__index_repository; writes sentinel file marking session as ready
- [ ] **REQ-08**: `hooks/project/agent-cmm-gate.sh` — PreToolUse:Agent, hard blocking gate (exit 2); blocks subagent spawning if CMM instructions are absent from the prompt; error message includes copy-paste instructions
- [ ] **REQ-09**: `hooks/project/track-cmm-calls.sh` — PostToolUse:mcp__codebase-memory-mcp__*; logs call counts per tool to ~/.cache/codebase-memory-mcp/_call-counts.json

### Rules + Config Templates
- [ ] **REQ-10**: `rules/global-claude-md.md` — CLAUDE.md rules block for global ~/.claude/CLAUDE.md
- [ ] **REQ-11**: `rules/project-settings-example.json` — example .claude/settings.json showing all hook registrations
- [ ] **REQ-12**: `rules/mcp-example.json` — example .mcp.json for project-level MCP server registration
- [ ] **REQ-13**: `rules/allowed-tools.txt` — MCP tool allowlist for .claude/settings.local.json

### Setup Script
- [ ] **REQ-14**: `setup.sh` — automated install; detects global vs project mode; copies appropriate hooks; applies settings.json merges; chmod +x

## Out of Scope

- Statusline script file (README includes example integration code only)
- Post-commit reindex hook (CMM auto-sync handles this; docs mention it)
- Token savings tracking (CMM doesn't expose tokens_saved in tool responses)
