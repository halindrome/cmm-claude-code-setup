#!/bin/bash
# Parse a Claude Code session JSONL file and emit per-session token totals as a CSV line

if [ -z "$1" ]; then
  echo "Usage: $0 <session.jsonl>" >&2
  exit 1
fi

if [ ! -f "$1" ]; then
  echo "Error: File not found: $1" >&2
  exit 1
fi

jq -r -s '[.[] | select(.message.usage != null) | .message.usage | {
  input: (.input_tokens // 0),
  output: (.output_tokens // 0),
  cache_creation: (.cache_creation_input_tokens // 0),
  cache_read: (.cache_read_input_tokens // 0)
}] | {
  input: (map(.input) | add // 0),
  output: (map(.output) | add // 0),
  cache_creation: (map(.cache_creation) | add // 0),
  cache_read: (map(.cache_read) | add // 0)
} | "\(.input),\(.output),\(.cache_creation),\(.cache_read),\(.input + .output + .cache_creation + .cache_read)"' "$1"
