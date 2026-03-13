---
phase: 02
plan: 01
title: "Write cmm-nudge.sh global hook"
wave: 1
depends_on: []
must_haves:
  - NON-BLOCKING (always exit 0, advisory only)
  - Checks FILE_PATH extension against broad CMM language list
  - Exceptions for small files (<50 lines), meta files, .vbw-planning/, .claude/ paths
  - Short advisory message to stdout mentioning CMM graph tools
  - Install comment header with purpose, install instructions, matcher info
  - "#!/bin/bash shebang"
---

# Plan 01: Write cmm-nudge.sh global hook

## Output File
`hooks/global/cmm-nudge.sh`

## Task 1: Create the hook script

Create `hooks/global/cmm-nudge.sh` with the following implementation:

### File Header
```
#!/bin/bash
# PreToolUse:Read hook — advisory reminder to use CMM graph tools instead of Read
# NON-BLOCKING: always exits 0 (advisory only, never blocks)
#
# Install: cp hooks/global/cmm-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-nudge.sh
# Register in ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Read", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-nudge.sh"}] }] }
```

### Input Parsing
Read JSON from stdin, extract `file_path` using python3:
```bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)
```
If FILE_PATH is empty, exit 0 immediately.

### Exception: Meta/Config Files (check BEFORE extension match)
Exit 0 silently for these basenames:
- CLAUDE.md, MEMORY.md, README.md, CHANGELOG.md, LICENSE, LICENSE.md
- Any file matching `*-PLAN.md`, `*-RESEARCH.md`, `*-CONTEXT.md`
- conftest.py, setup.py, setup.cfg, pyproject.toml, package.json, tsconfig.json, Cargo.toml, go.mod, go.sum

### Exception: Planning/Config Paths
Exit 0 silently if FILE_PATH contains:
- `/.vbw-planning/`
- `/.planning/`
- `/.claude/`
- `/node_modules/`
- `/.git/`

### Extension Check — CMM Supported Languages
Check FILE_PATH extension against this list (derived from CMM's 64 supported languages). Use a bash `case` statement:

```
*.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.cxx|*.c|*.h|*.hpp|*.cs|*.php|*.lua|*.scala|*.kt|*.kts|*.rb|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|*.hs|*.ml|*.mli|*.m|*.mm|*.swift|*.dart|*.pl|*.pm|*.groovy|*.erl|*.hrl|*.r|*.R|*.clj|*.cljs|*.cljc|*.fs|*.fsx|*.fsi|*.jl|*.vim|*.nix|*.lisp|*.cl|*.elm|*.f90|*.f95|*.f03|*.cu|*.cuh|*.cob|*.cbl|*.v|*.sv|*.el|*.lean|*.frm|*.wl|*.wls|*.html|*.css|*.scss|*.sass|*.yaml|*.yml|*.toml|*.hcl|*.tf|*.sql|*.vue|*.svelte|*.graphql|*.gql|*.proto|*.cmake|*.glsl|*.ini|*.cfg
```

If the extension does NOT match, exit 0 (not a CMM-indexed file type).

### Exception: Small Files (<50 lines)
If the file exists and has fewer than 50 lines, exit 0:
```bash
if [ -f "$FILE_PATH" ] && [ "$(wc -l < "$FILE_PATH" 2>/dev/null)" -lt 50 ]; then
  exit 0
fi
```

### Advisory Output
If all checks pass (it IS a source file, NOT an exception), print the advisory:
```
echo "Tip: CMM graph tools (search_graph, get_code_snippet, trace_call_path) may be faster than Read for codebase exploration."
```

### Exit
Always `exit 0`. The script must NEVER exit with a non-zero code.

### Permissions
File must be created with executable permission (chmod +x).

## Acceptance Criteria
- [ ] File exists at `hooks/global/cmm-nudge.sh`
- [ ] Script always exits 0 regardless of input
- [ ] Header includes purpose, install instructions, matcher
- [ ] Shebang is `#!/bin/bash`
- [ ] Extensions cover CMM's 64 languages
- [ ] Meta files (CLAUDE.md, MEMORY.md, etc.) are excluded
- [ ] Planning paths (.vbw-planning/, .claude/) are excluded
- [ ] Small files (<50 lines) are excluded
- [ ] Advisory message mentions search_graph, get_code_snippet, trace_call_path
