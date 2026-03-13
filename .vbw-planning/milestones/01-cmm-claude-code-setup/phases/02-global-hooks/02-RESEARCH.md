# Phase 02 Research: Global Hooks

## Findings

### Language Support

CMM supports 64 languages (from README line 11):
Python, Go, JavaScript, TypeScript, TSX, Rust, Java, C++, C#, C, PHP, Lua, Scala, Kotlin, Ruby, Bash, Zig, Elixir, Haskell, OCaml, Objective-C, Swift, Dart, Perl, Groovy, Erlang, R, Clojure, F#, Julia, Vim Script, Nix, Common Lisp, Elm, Fortran, CUDA, COBOL, Verilog, Emacs Lisp, MATLAB, Lean 4, FORM, Magma, Wolfram, HTML, CSS, SCSS, YAML, TOML, HCL, SQL, Dockerfile, JSON, XML, Markdown, Makefile, CMake, Protobuf, GraphQL, Vue, Svelte, Meson, GLSL, INI

jmunch's nudge hook only checked `.py`, `.ts`, `.tsx` — far too narrow. CMM's nudge should include at minimum: `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go`, `.rs`, `.java`, `.cpp`, `.c`, `.rb`, `.php`, `.sh`, `.swift`, `.kt`, `.cs`, `.m`, `.scala`.

### Hook Behavior (Critical Difference from jmunch)

**jcodemunch-nudge.sh**: BLOCKING (exit 2) — blocks the Read call
**cmm-nudge.sh**: NON-BLOCKING (exit 0) — advisory only, per REQ-03

The nudge must always exit 0. Never block. Output an advisory reminder to stdout.

### Input Parsing

Hook receives JSON via stdin:
```bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)
```

For PostToolUse (Write/Edit), use jq:
```bash
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
```

### Debounce Mechanism (reindex-after-edit.sh)

Current jmunch uses 30s debounce. REQ-04 specifies 60s for CMM.

```bash
STAMP="/tmp/cmm-reindex-stamp-$(id -u)"
if [ -f "$STAMP" ]; then
  LAST=$(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  [ $((NOW - LAST)) -lt 60 ] && exit 0
fi
touch "$STAMP"
```

Platform-agnostic `stat`: macOS uses `-f %m`, Linux uses `-c %Y`.

### settings.json Hook Registration

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-nudge.sh"}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/reindex-after-edit.sh"}]
      }
    ]
  }
}
```

Global hooks: registered in `~/.claude/settings.json` (not project-level `.claude/settings.json`).

### CMM Tool Prefix

All CMM tools use: `mcp__codebase-memory-mcp__*`
Key tools to mention in nudge: `search_graph`, `trace_call_path`, `get_code_snippet`, `get_architecture`

### Exception Patterns (from jmunch)

Three-level exception system to preserve:
1. Filename exceptions: CLAUDE.md, MEMORY.md, README.md, *-PLAN.md
2. Path exceptions: .vbw-planning/*, .claude/*, planning files
3. Size exceptions: files < 50 lines (allow small files — overhead not worth nudging)

## Relevant Patterns

1. **Non-blocking nudge**: Always exit 0. Output advisory message to stdout. Short (1-2 lines).
2. **Cross-platform stat**: `stat -f %m` (macOS) || `stat -c %Y` (Linux) || echo 0.
3. **Input parsing**: `python3 -c "import sys,json..."` for PreToolUse (file_path); `jq` for PostToolUse.
4. **Debounce temp file**: `/tmp/cmm-reindex-stamp-$(id -u)` (per-user, persistent across sessions).
5. **shebang**: `#!/bin/bash` per project convention.

## Risks

1. **Language list obsolescence**: CMM adds languages over time — list in hook will need updates. Comment clearly.
2. **jq dependency**: reindex-after-edit.sh needs jq. Add python3 fallback or document requirement.
3. **60s debounce granularity**: Rapid edits may not trigger prompt. Document this as expected behavior.
4. **Tool prefix changes**: If CMM renames tools, hook suggestions become stale. Comment the prefix.

## Recommendations

### cmm-nudge.sh
- `#!/bin/bash`, exit 0 always
- Check FILE_PATH extension against broad language list (core extensions + CMM-specific)
- Exception: small files (<50 lines), config/meta files (CLAUDE.md etc.), paths in .vbw-planning/, .claude/
- Output single advisory line: "Tip: For codebase exploration, CMM graph tools (search_graph, get_code_snippet, trace_call_path) are faster than Read."
- Include install location comment at top: `# Install: cp cmm-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-nudge.sh`

### reindex-after-edit.sh
- `#!/bin/bash`, exit 0 always
- 60s debounce via `/tmp/cmm-reindex-stamp-$(id -u)`
- Check FILE_PATH extension against same broad language list
- If debounce passes: output prompt "A source file was modified. Consider running index_repository to refresh the CMM graph (auto-sync may handle this)."
- Graceful fallback if jq missing

### File headers
Both scripts should include:
- Purpose (one line)
- Install instructions (copy to ~/.claude/hooks/, chmod +x, register in ~/.claude/settings.json)
- Matcher (PreToolUse:Read / PostToolUse:Write|Edit)
