#!/bin/bash
# generate-checksums.sh — Regenerates CHECKSUMS.sha256 for release verification
# Run from repo root before tagging a release: bash scripts/generate-checksums.sh
#
# Covers: hooks/, rules/, setup.sh (all files distributed to users)
# Output: CHECKSUMS.sha256 at repo root (commit this file with the release)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "Generating CHECKSUMS.sha256..."
find hooks/ rules/ setup.sh -type f | LC_ALL=C sort | xargs shasum -a 256 > CHECKSUMS.sha256
echo "✓ Written to CHECKSUMS.sha256 ($(wc -l < CHECKSUMS.sha256 | tr -d ' ') files)"
