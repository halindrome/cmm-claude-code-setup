#!/bin/bash
# ctx-shell-compat.sh — PreToolUse hook: warn about bash-only syntax in Context Mode shell payloads.
# ADVISORY: always exits 0, emits additionalContext. Never blocks.
#
# Install: cp hooks/project/ctx-shell-compat.sh .claude/hooks/ && chmod +x .claude/hooks/ctx-shell-compat.sh
# Register in .claude/settings.json (plugin-form names FIRST, MCP-server-form second):
#   "hooks": { "PreToolUse": [{
#     "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute|mcp__plugin_context-mode_context-mode__ctx_execute_file|mcp__plugin_context-mode_context-mode__ctx_batch_execute|mcp__context-mode__ctx_execute|mcp__context-mode__ctx_execute_file|mcp__context-mode__ctx_batch_execute",
#     "hooks": [{"type": "command", "command": "bash .claude/hooks/ctx-shell-compat.sh"}] }] }
#
# WHY THIS EXISTS: context-mode resolves ONE "shell" runtime — $SHELL when its basename is
#   allowlisted, else bash (see context-mode src/runtime.ts detectRuntimes()). On a default macOS
#   install that is zsh, and there is no "bash" key in the RuntimeMap, so language="bash" cannot
#   select bash either. Agents write bash and get zsh.
#
# WHY ADVISORY, NOT BLOCKING (unlike ctx-payload-guard.sh): truncation is unambiguously wrong and
#   has one correct replacement. Shell-dialect issues are a correctness hint on code that may be
#   fine — `${!x}` inside a quoted heredoc destined for a remote bash, say. A wrong block here
#   would stop legitimate work, and a gate that names no usable alternative sends 90-95% of blocks
#   straight back to raw tools (measured on cwd-guard).
#
# SCALE, HONESTLY: only 0.7% of 27,367 measured ctx calls carried any shell-error signature, so
#   this is far smaller than the truncation gap. `${!var}` is the sharp case: 141 uses, 18.6% of
#   them failing with `zsh: bad substitution` — the highest failure rate of any construct measured,
#   each costing a full retry round-trip. The word-splitting case is included precisely because it
#   fails SILENTLY and leaves no error to measure.

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

read -r -d '' _PY <<'PYEOF' || true
import json, re, sys

ACCEPTED = {
    "mcp__plugin_context-mode_context-mode__ctx_execute",
    "mcp__plugin_context-mode_context-mode__ctx_execute_file",
    "mcp__plugin_context-mode_context-mode__ctx_batch_execute",
    "mcp__context-mode__ctx_execute",
    "mcp__context-mode__ctx_execute_file",
    "mcp__context-mode__ctx_batch_execute",
}
SHELLY = {"shell", "bash", "sh", "zsh", "", None}

# (regex, what it is, the zsh-safe replacement)
CHECKS = [
    (re.compile(r"\$\{!\w"), "${!var} (bash indirect expansion)",
     'use ${(P)var}, or wrap the payload in bash -c "..."'),
    (re.compile(r"\b(?:mapfile|readarray)\b"), "mapfile/readarray (bash builtin)",
     'use arr=("${(@f)$(cmd)}"), or wrap in bash -c "..."'),
    (re.compile(r"\b(?:declare|local)\s+-n\b"), "declare -n / local -n (bash nameref)",
     'wrap in bash -c "..." — zsh has no nameref'),
    (re.compile(r"\$\{\w+(?:\^\^|,,)"), "${var^^} / ${var,,} (bash case conversion)",
     "use ${var:u} / ${var:l}"),
    (re.compile(r"\bread\s+(?:-\w*\s+)*-a\b"), "read -a (bash array read)",
     "use read -A"),
    (re.compile(r"\bfor\s+\w+\s+in\s+\$\w+\s*[;\n]"), "for f in $unquoted (word splitting)",
     'zsh does NOT split unquoted $var: this iterates ONCE over the whole string. '
     'Use ${=var} to force splitting, or an array, or bash -c "...". '
     'This one fails SILENTLY — no error, just a wrong answer'),
]


def payloads(tool, ti):
    if tool.endswith("ctx_batch_execute"):
        return [("shell", c["command"]) for c in (ti.get("commands") or [])
                if isinstance(c, dict) and isinstance(c.get("command"), str)]
    code = ti.get("code")
    if isinstance(code, str):
        return [(ti.get("language"), code)]
    return []


try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = d.get("tool_name") or ""
if tool not in ACCEPTED:
    sys.exit(0)

found = []
for lang, text in payloads(tool, d.get("tool_input") or {}):
    if (lang or "").lower() not in SHELLY:
        continue
    for rx, what, fix in CHECKS:
        if rx.search(text) and what not in [f[0] for f in found]:
            found.append((what, fix))

if not found:
    sys.exit(0)

lines = ["[ctx-shell-compat] This payload runs under $SHELL (zsh here), not bash. "
         "language=\"bash\" is not a distinct runtime and will not select bash."]
for what, fix in found[:4]:
    lines.append("  - %s -> %s" % (what, fix))
lines.append("Advisory only - the call was allowed.")
msg = "\n".join(lines)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                         "additionalContext": msg}}))
PYEOF

printf '%s' "$INPUT" | python3 -c "$_PY" 2>/dev/null || true

exit 0
