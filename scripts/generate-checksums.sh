#!/bin/bash
# generate-checksums.sh — Regenerates CHECKSUMS.sha256 for release verification
# Run from repo root before tagging a release: bash scripts/generate-checksums.sh
#
# Covers: hooks/, rules/, agents/, setup.sh (all files distributed to users)
# Output: CHECKSUMS.sha256 at repo root (commit this file with the release)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

SHASUM_CMD=""
if command -v shasum >/dev/null 2>&1; then
  SHASUM_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHASUM_CMD="sha256sum"
else
  echo "Error: neither shasum nor sha256sum found" >&2
  exit 1
fi

echo "Generating CHECKSUMS.sha256..."
find hooks/ rules/ agents/ setup.sh -type f | LC_ALL=C sort | xargs $SHASUM_CMD > CHECKSUMS.sha256
echo "✓ Written to CHECKSUMS.sha256 ($(wc -l < CHECKSUMS.sha256 | tr -d ' ') files)"
