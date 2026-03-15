#!/bin/bash
# Find the most recent Claude Code session JSONL file, optionally scoped by project path or timestamp

AFTER_TS=""
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --after) AFTER_TS="$2"; shift 2 ;;
    *) PROJECT_PATH="$1"; shift ;;
  esac
done

SESSIONS_GLOB="${CLAUDE_SESSIONS_DIR:-$HOME/.config/claude-code/projects}/*/*.jsonl"

# Collect candidates sorted by modification time (newest first)
CANDIDATES=$(ls -t ${SESSIONS_GLOB} 2>/dev/null)

if [ -z "$CANDIDATES" ]; then
  echo "Error: No session files found" >&2
  exit 1
fi

# If a project path was given, filter by hashed project dir
if [ -n "$PROJECT_PATH" ]; then
  # Claude Code hashes project paths by replacing / with - and removing leading -
  HASHED=$(echo "$PROJECT_PATH" | sed 's|/|-|g' | sed 's|^-||')
  CANDIDATES=$(echo "$CANDIDATES" | grep "/${HASHED}/" 2>/dev/null)
  if [ -z "$CANDIDATES" ]; then
    echo "Error: No session files found for project: $PROJECT_PATH" >&2
    exit 1
  fi
fi

# If --after timestamp given, filter to files modified after that time
if [ -n "$AFTER_TS" ]; then
  FILTERED=""
  while IFS= read -r f; do
    MTIME=$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)
    if [ -n "$MTIME" ] && [ "$MTIME" -gt "$AFTER_TS" ]; then
      FILTERED="${FILTERED}${f}"$'\n'
    fi
  done <<< "$CANDIDATES"
  CANDIDATES="$FILTERED"
  if [ -z "$(echo "$CANDIDATES" | tr -d '[:space:]')" ]; then
    echo "Error: No session files found after timestamp $AFTER_TS" >&2
    exit 1
  fi
fi

# Return the most recent (first after sort by mtime)
LATEST=$(echo "$CANDIDATES" | head -1)
echo "$LATEST"
