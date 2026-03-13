---
phase: 02
plan: 02
title: "Write reindex-after-edit.sh global hook"
wave: 1
depends_on: []
must_haves:
  - NON-BLOCKING (always exit 0, advisory only)
  - 60s debounce via /tmp/cmm-reindex-stamp-$(id -u)
  - Cross-platform stat (macOS -f %m / Linux -c %Y)
  - Checks FILE_PATH extension against broad CMM language list
  - Advisory prompt after debounce passes
  - Graceful fallback if jq is missing
  - "#!/bin/bash shebang"
---

# Plan 02: Write reindex-after-edit.sh global hook

## Output File
`hooks/global/reindex-after-edit.sh`

## Task 1: Create the hook script

Create `hooks/global/reindex-after-edit.sh` with the following implementation:

### File Header
```
#!/bin/bash
# PostToolUse:Write|Edit hook — advisory reminder to re-index after source file edits
# NON-BLOCKING: always exits 0 (advisory only, never blocks)
# Debounce: 60 seconds between prompts
#
# Install: cp hooks/global/reindex-after-edit.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/reindex-after-edit.sh
# Register in ~/.claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "Write|Edit", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/reindex-after-edit.sh"}] }] }
```

### Input Parsing with jq Fallback
Parse JSON from stdin to extract the file path. Try jq first, fall back to python3:
```bash
INPUT=$(cat)

# Try jq first, fall back to python3
if command -v jq >/dev/null 2>&1; then
  FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
else
  FILE=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('file_path', '') or ti.get('path', ''))
" 2>/dev/null)
fi
```
If FILE is empty, exit 0 immediately.

### Extension Check — CMM Supported Languages
Check FILE extension against the same broad language list as cmm-nudge.sh. Use a bash `case` statement:

```
*.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.cxx|*.c|*.h|*.hpp|*.cs|*.php|*.lua|*.scala|*.kt|*.kts|*.rb|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|*.hs|*.ml|*.mli|*.m|*.mm|*.swift|*.dart|*.pl|*.pm|*.groovy|*.erl|*.hrl|*.r|*.R|*.clj|*.cljs|*.cljc|*.fs|*.fsx|*.fsi|*.jl|*.vim|*.nix|*.lisp|*.cl|*.elm|*.f90|*.f95|*.f03|*.cu|*.cuh|*.cob|*.cbl|*.v|*.sv|*.el|*.lean|*.frm|*.wl|*.wls|*.html|*.css|*.scss|*.sass|*.yaml|*.yml|*.toml|*.hcl|*.tf|*.sql|*.vue|*.svelte|*.graphql|*.gql|*.proto|*.cmake|*.glsl|*.ini|*.cfg
```

If the extension does NOT match, exit 0 (not a CMM-indexed file type).

### Debounce Logic (60 seconds)
Use a per-user timestamp file to debounce:
```bash
STAMP="/tmp/cmm-reindex-stamp-$(id -u)"
if [ -f "$STAMP" ]; then
  # Cross-platform stat: macOS uses -f %m, Linux uses -c %Y
  LAST=$(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [ $((NOW - LAST)) -lt 60 ]; then
    exit 0
  fi
fi
touch "$STAMP"
```

Key details:
- Stamp file path: `/tmp/cmm-reindex-stamp-$(id -u)` (per-user, persists across sessions)
- `stat -f %m` is macOS syntax for file modification time in epoch seconds
- `stat -c %Y` is Linux syntax for the same
- Falls back to `echo 0` if both fail (forces prompt)
- 60-second window: if last prompt was <60s ago, exit silently

### Advisory Output
If debounce passes (>60s since last prompt or first edit), print the advisory:
```
echo "A source file was modified. Consider running index_repository to refresh the CMM graph (auto-sync may handle this)."
```

### Exit
Always `exit 0`. The script must NEVER exit with a non-zero code.

### Permissions
File must be created with executable permission (chmod +x).

## Acceptance Criteria
- [ ] File exists at `hooks/global/reindex-after-edit.sh`
- [ ] Script always exits 0 regardless of input
- [ ] Header includes purpose, install instructions, matcher, debounce info
- [ ] Shebang is `#!/bin/bash`
- [ ] jq fallback to python3 works gracefully
- [ ] Extensions cover CMM's 64 languages (same list as cmm-nudge.sh)
- [ ] Debounce uses `/tmp/cmm-reindex-stamp-$(id -u)` with 60s window
- [ ] Cross-platform stat works on both macOS and Linux
- [ ] Advisory message mentions index_repository and auto-sync
