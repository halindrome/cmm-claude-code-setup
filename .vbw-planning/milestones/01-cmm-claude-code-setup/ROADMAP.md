# cmm-claude-code-setup Roadmap

Hook-based enforcement layer for codebase-memory-mcp + Claude Code, adapted from Shachar Bard's jmunch-claude-code-setup.

## Phases
- [x] Phase 1: Core Documentation
- [x] Phase 2: Global Hooks
- [x] Phase 3: Project Hooks
- [x] Phase 4: Rules + Config Templates
- [x] Phase 5: Setup Script

### Phase 1: Core Documentation
**Goal:** Write README.md (with prominent attribution to Shachar Bard) and docs/setup-guide.md (migrating and expanding existing guide content). These are the primary entry points for users.
**Deps:** none
**Reqs:** REQ-01, REQ-02
**Success:** README.md exists with attribution at top, Quick Start, structure overview, statusline example; docs/setup-guide.md covers full installation walkthrough including hooks

### Phase 2: Global Hooks
**Goal:** Write the two global hooks that install to ~/.claude/hooks/ and apply soft enforcement across all projects.
**Deps:** Phase 1
**Reqs:** REQ-03, REQ-04
**Success:** cmm-nudge.sh correctly detects source files and outputs reminder text (exit 0); reindex-after-edit.sh debounces and prompts re-index; both are properly commented with install instructions

### Phase 3: Project Hooks
**Goal:** Write the five project-level hooks that install to .claude/hooks/ and provide hard blocking enforcement for a specific project.
**Deps:** Phase 1
**Reqs:** REQ-05, REQ-06, REQ-07, REQ-08, REQ-09
**Success:** Session start injects correct prompt; gate correctly blocks tools and allows CMM tools; sentinel writer unblocks on index_repository completion; agent gate blocks and provides copy-paste instructions; call tracker writes JSON correctly

### Phase 4: Rules + Config Templates
**Goal:** Write the four rules/config template files users copy into their project.
**Deps:** Phase 2, Phase 3
**Reqs:** REQ-10, REQ-11, REQ-12, REQ-13
**Success:** global-claude-md.md covers all CMM tool usage patterns; settings.json example shows all hook registrations; mcp-example.json is valid; allowed-tools.txt is complete

### Phase 5: Setup Script
**Goal:** Write setup.sh that automates the full installation process.
**Deps:** Phase 2, Phase 3, Phase 4
**Reqs:** REQ-14
**Success:** setup.sh correctly copies hooks to correct locations (global or project), merges settings.json, sets permissions, and confirms installation

## Progress
| Phase | Done | Status | Date |
|-------|------|--------|------|
| 1 - Core Documentation | 2/2 | complete | 2026-03-12 |
| 2 - Global Hooks | 2/2 | complete | 2026-03-12 |
| 3 - Project Hooks | 5/5 | complete | 2026-03-12 |
| 4 - Rules + Config Templates | 4/4 | complete | 2026-03-12 |
| 5 - Setup Script | 1/1 | complete | 2026-03-12 |
