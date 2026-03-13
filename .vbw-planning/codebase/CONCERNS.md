# Concerns

## Maintenance Risk
- Guide may drift from actual `codebase-memory-mcp` API as the package evolves
- Tool names (e.g., `mcp__codebase-memory-mcp__*`) are hardcoded throughout

## Scope Creep Risk
- Guide currently covers global setup; per-project variations could proliferate

## Platform Specificity
- `stat -f %m` (macOS) vs `stat -c %Y` (Linux) in the reindex hook handles both
- PATH setup for npm globals differs by OS/shell (not documented)

## No Versioning
- Guide doesn't specify which codebase-memory-mcp version it covers
- No changelog or version pinning mentioned
