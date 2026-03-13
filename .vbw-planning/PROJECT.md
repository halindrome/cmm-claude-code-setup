# cmm-claude-code-setup

Hooks, rules, and documentation for tight integration of [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) with Claude Code — enforcement layer inspired by [Shachar Bard's jmunch-claude-code-setup](https://github.com/shacharbard).

**Core value:** Make Claude Code reliably use the codebase-memory-mcp knowledge graph instead of falling back to Read, through hook-based enforcement, CLAUDE.md rules, and an automated setup script.

## Requirements

### Validated
- Attribution to Shachar Bard (shacharbard) prominently in README

### Active
- [ ] README.md with full attribution, overview, Quick Start, statusline example
- [ ] docs/setup-guide.md migrating existing codebase-memory-setup-guide.md content
- [ ] Global hooks: cmm-nudge.sh (non-blocking, broad language), reindex-after-edit.sh
- [ ] Project hooks: session start, session gate, sentinel writer, agent gate, call tracker
- [ ] Rules: CLAUDE.md template, settings.json example, mcp.json example, allowed-tools.txt
- [ ] setup.sh automated install script

### Out of Scope
- Statusline script file (README example only)
- Post-commit reindex hook (CMM auto-sync handles this; docs mention only)
- Token savings tracking (CMM doesn't report tokens_saved per call)

## Constraints
- **No new dependencies**: Bash + jq + python3 only (same as jmunch)
- **Attribution required**: Shachar Bard cited prominently at top of README
- **Language list dynamic**: Nudge hook should be extensible as CMM adds language support
- **MIT license**: Match jmunch license

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Non-blocking nudge | Softer enforcement reduces false positives on small files | exit 0 with reminder text |
| Both global + project hooks | Global for soft enforcement, project for hard gate | Two-tier structure mirrors jmunch |
| No statusline script | Statusline stats vary by user setup; README example is sufficient | Docs-only approach |
| CMM call counter | CMM has no tokens_saved field; call counts provide proxy metric | track-cmm-calls.sh |
