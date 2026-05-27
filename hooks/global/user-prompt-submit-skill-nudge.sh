#!/bin/bash
# user-prompt-submit-skill-nudge.sh — UserPromptSubmit: inject skill activation when prompt contains code-navigation verbs
# Fires on every user prompt in both main session and subagents.
# Emits additionalContext JSON when the prompt contains code-navigation verbs.
# Silent no-op otherwise. Fail-open on any parse error.
#
# Install: cp hooks/global/user-prompt-submit-skill-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/user-prompt-submit-skill-nudge.sh
# Register in ~/.claude/settings.json under UserPromptSubmit:
#   "hooks": { "UserPromptSubmit": [{ "matcher": "*",
#                                     "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/user-prompt-submit-skill-nudge.sh"}] }] }
# Matcher: UserPromptSubmit:*

# --- Input Parsing (fail-open on every parse path) ---
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Extract prompt text from the UserPromptSubmit payload (.prompt or .userPrompt field)
PROMPT_TEXT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
text = d.get('prompt', '') or d.get('userPrompt', '') or ''
if not isinstance(text, str):
    sys.exit(0)
print(text)
" 2>/dev/null) || exit 0

[ -z "$PROMPT_TEXT" ] && exit 0

# --- Code-navigation verb detection ---
# Match common code-navigation patterns that benefit from CMM + ctx-rules
if ! echo "$PROMPT_TEXT" | grep -qiE '\b(find|trace|show me|what calls|who calls|refactor|explore|navigate|search|grep|where is|what does|imports|depends|callers|how is)\b'; then
    exit 0
fi

# --- Emit skill activation advisory ---
NUDGE_TEXT="Invoke Skill('cmm-rules') via the Skill tool now, then Invoke Skill('ctx-rules') via the Skill tool now."
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":sys.argv[1]}}))' \
    "$NUDGE_TEXT"

exit 0
