#!/bin/bash
# test-vbw2-checksums.sh — the CMM wrapper is covered by CHECKSUMS.sha256 (R5)
# hooks/ is a checksummed tree (scripts/generate-checksums.sh), so the wrapper
# must be listed there with a hash that verifies.
# Usage: bash tests/test-vbw2-checksums.sh
# Exit: 0 = pass, 1 = failure
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO"
LINE="$(grep -E '  hooks/project/cmm-query\.sh$' CHECKSUMS.sha256 || true)"
if [ -z "$LINE" ]; then
    echo "FAIL: CHECKSUMS.sha256 does not list hooks/project/cmm-query.sh"
    exit 1
fi
if printf '%s\n' "$LINE" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "PASS: hooks/project/cmm-query.sh listed and verified in CHECKSUMS.sha256"
else
    echo "FAIL: hooks/project/cmm-query.sh hash in CHECKSUMS.sha256 does not verify"
    exit 1
fi
