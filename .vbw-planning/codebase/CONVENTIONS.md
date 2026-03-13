# Conventions

## Documentation Style
- Step-by-step numbered sections (Step 1, Step 2...)
- Each step has a title, description, code block, and note block
- Code blocks use triple backticks with language tags (bash, json, markdown)
- Horizontal rules (`---`) separate major sections
- Blockquotes (`>`) for "Why this matters" callouts

## Shell Scripts
- Shebang: `#!/bin/bash`
- One-line comment describing the hook's purpose
- Read stdin via `INPUT=$(cat)`
- Early-exit pattern (`[ -z "$VAR" ] && exit 0`)
- Case statements for file extension matching

## JSON Config
- All Claude Code config uses camelCase keys
- Hooks use array-of-objects format: `[{"hooks": [...]}]`
- Type-discriminated hook format: `{"type": "command"|"prompt", ...}`
