#!/bin/bash
# Bump semantic version in version.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$REPO_ROOT/version.txt"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Error: $VERSION_FILE not found" >&2
  exit 1
fi

BUMP="${1}"

if [[ "$BUMP" == "--verify" ]]; then
  V1="$(cat "$VERSION_FILE" 2>/dev/null || echo "")"
  V2="$(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo "")"
  if [[ "$V1" != "$V2" ]]; then
    echo "MISMATCH: version.txt=$V1  VERSION=$V2" >&2
    exit 1
  fi
  exit 0
fi

if [[ "$BUMP" != "major" && "$BUMP" != "minor" && "$BUMP" != "patch" ]]; then
  echo "Usage: $0 major|minor|patch" >&2
  exit 1
fi

CURRENT="$(cat "$VERSION_FILE")"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW="$MAJOR.$MINOR.$PATCH"
echo "$NEW" > "$VERSION_FILE"
echo "$NEW" > "$REPO_ROOT/VERSION"
echo "Bumped $CURRENT → $NEW"
