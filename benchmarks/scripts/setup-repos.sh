#!/bin/bash
# Clone benchmark repos (shallow) into ~/.cache/cmm-benchmarks/repos/ if not already present
# Repos are stored OUTSIDE the project tree so CMM doesn't index them as part of this project.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../config.sh"

mkdir -p "$BENCH_REPOS_DIR"

exit_code=0

for repo in "${BENCH_REPOS[@]}"; do
  owner="${repo%%/*}"
  name="${repo##*/}"
  dest="$BENCH_REPOS_DIR/$owner/$name"

  if [ -d "$dest" ]; then
    echo "[ok]      $repo — already exists at $dest"
  else
    mkdir -p "$BENCH_REPOS_DIR/$owner"
    echo "[cloning] $repo → $dest"
    if git clone --depth 1 "https://github.com/$repo.git" "$dest"; then
      echo "[done]    $repo"
    else
      echo "[error]   Failed to clone $repo" >&2
      exit_code=1
    fi
  fi
done

exit $exit_code
