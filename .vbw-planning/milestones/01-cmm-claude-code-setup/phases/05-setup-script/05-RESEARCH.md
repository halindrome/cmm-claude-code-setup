# Phase 05 Research: Setup Script

## Findings

### JSON Merging Approach

**Key Design Pattern:** The project uses `python3` as the primary JSON manipulation tool with graceful fallback. This is consistent with `track-cmm-calls.sh` atomic write pattern (python3 + temp file + os.replace).

**For setup.sh merging:**
- **Global settings.json**: Merge into `$HOME/.claude/settings.json`
- **Project settings.json**: Merge into `./.claude/settings.json` (relative to current directory)
- Both files may already exist with partial configurations
- **Merge strategy**: Deep merge hooks arrays (append new hook entries to existing arrays; do NOT replace)
- Python3 is more reliable than jq for this (python3 is standard on macOS/Linux; jq is optional)

---

### Global vs Project Installation Flags

**Recommended approach: CLI flags + interactive fallback**

- `--global` flag: Install global hooks only (copy to `~/.claude/hooks/`, merge into `~/.claude/settings.json`)
- `--project` flag: Install project hooks only (copy to `./.claude/hooks/`, merge into `./.claude/settings.json`)
- `--all` flag: Install both global and project
- No flag (default): Interactive prompt asking "Global, project, or both? (g/p/a)"

---

### Hook Path Formats in settings.json

**Global hooks** (`~/.claude/settings.json`):
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/cmm-nudge.sh\""}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/reindex-after-edit.sh\""}]
      }
    ]
  }
}
```

**Project hooks** (`./.claude/settings.json`): Use relative paths exactly as in `rules/project-settings-example.json` — e.g., `"bash .claude/hooks/cmm-session-start.sh"`.

**Critical difference:**
- Global: Absolute path with `$HOME` (in double-quotes to allow `$` expansion)
- Project: Relative path (relative to project root)

---

### Existing settings.json Handling

- If file exists: read it, deep-merge hooks, write back
- If file does NOT exist: create `$HOME/.claude/` or `./.claude/` dir, write from example
- **Never** overwrite entire file — always merge
- After write: validate JSON syntax with `python3 -m json.tool`
- Keep `.backup` of original before merge

---

### Binary Installation

**Do NOT install codebase-memory-mcp binary in setup.sh.**
- Warn if binary is missing on PATH
- Document that users must install binary first
- Only check: `command -v codebase-memory-mcp`

---

### Rules Directory Handling

For project install: copy `rules/` to `./.claude/rules/` for reference. The `.mcp.json` file is created from `rules/mcp-example.json` at project root.

---

## Relevant Patterns

### Installation Step Pattern (from hook headers)
```bash
# Install: cp hooks/global/cmm-nudge.sh ~/.claude/hooks/
#          chmod +x ~/.claude/hooks/cmm-nudge.sh
# Register in ~/.claude/settings.json
```

Three-step pattern (copy → chmod → register) is what setup.sh automates.

### Python3 JSON Merge Pattern (from track-cmm-calls.sh)
```python
import json, os, sys, tempfile
try:
    with open(settings_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
# merge logic
tmp = settings_file + '.tmp'
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2)
os.replace(tmp, settings_file)
```

### Prerequisite Check Pattern
```bash
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required but not found." >&2
  exit 1
fi
```

### Force Flag Pattern
```bash
if [ -f "$TARGET" ] && [ "$FORCE" != true ]; then
  echo "  ⊘ $(basename "$TARGET") already exists; skipping (use --force to overwrite)"
else
  cp "$SOURCE" "$TARGET"
  echo "  ✓ Copied $(basename "$TARGET")"
fi
```

---

## Risks

1. **JSON merge conflicts**: User may have existing hooks with same matchers → duplicates. Mitigation: append entries; document deduplication is manual.
2. **$HOME vs ~ in paths**: Always use `$HOME` in scripts, never `~` in embedded JSON.
3. **Permissions not set**: If chmod fails, hooks won't execute. Check exit code.
4. **Relative vs absolute paths in project mode**: Warn user to run from repo root.
5. **Overwriting existing hooks**: Check for existing files; skip with `--force` offer.
6. **Python3 not available**: Check early, fail with helpful install instructions.

---

## Recommendations

### 1. CLI Interface
```
setup.sh [--global] [--project] [--all] [--force] [--dry-run]

--global     Install global hooks (~/.claude/hooks/)
--project    Install project hooks (./.claude/hooks/)
--all        Install both global and project
--force      Overwrite existing hooks and settings
--dry-run    Show what would be done without making changes
```
No flags → interactive prompt.

### 2. Prerequisites Check
```bash
- python3 --version (required)
- codebase-memory-mcp --version (optional, warn if missing)
- hooks/ directory exists (required)
- rules/ directory exists (required for --project)
```

### 3. Global Settings JSON Content
Hardcode the exact hook entries for global hooks (do NOT read from external file — global settings format differs from project-settings-example.json):
```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Read", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/cmm-nudge.sh\""}]}
    ],
    "PostToolUse": [
      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/reindex-after-edit.sh\""}]}
    ]
  }
}
```

### 4. Project Settings JSON Content
Read directly from `rules/project-settings-example.json` (already in correct format for `.claude/settings.json`).

### 5. Dry-Run Support
Print `[DRY RUN] Would copy X to Y` without executing. Useful for auditing.

### 6. Status Reporting
```
[GLOBAL INSTALL]
  ✓ Created ~/.claude/hooks/
  ✓ Copied cmm-nudge.sh
  ✓ Copied reindex-after-edit.sh
  ✓ Set permissions (chmod +x)
  ✓ Merged hooks into ~/.claude/settings.json
  ✓ Validated JSON syntax

[PROJECT INSTALL]
  ✓ Created .claude/hooks/
  ✓ Copied 5 project hooks
  ✓ Set permissions (chmod +x)
  ✓ Created .mcp.json
  ✓ Merged hooks into .claude/settings.json
  ✓ Validated JSON syntax

Installation complete.
Next: Restart Claude Code to activate hooks
```

### 7. After-Install Summary
Always end with "Next steps" block reminding user to:
1. Restart Claude Code to activate hooks
2. If project install: run `index_repository` on first session
3. If global install: hooks will fire on next Read/Write/Edit
