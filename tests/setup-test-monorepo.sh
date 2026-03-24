#!/bin/bash
# setup-test-monorepo.sh — Creates an ephemeral monorepo fixture in /tmp for CMM touch_project testing.
# Fixture structure:
#   cmm-test-monorepo/               <- monorepo root (superproject)
#     apps/alpha/                    <- submodule (level 1)
#       vendor/core/                 <- nested submodule (level 2, inside apps/alpha)
#     apps/beta/                     <- submodule (level 1)
#     shared-lib/                    <- top-level submodule (level 1)
#
# Usage: source tests/setup-test-monorepo.sh
#        echo $CMM_TEST_MONOREPO_ROOT
# Or:    bash tests/setup-test-monorepo.sh  (prints root path to stdout)

set -e

# 1. Cleanup stale fixtures
rm -rf /tmp/cmm-test-monorepo-* 2>/dev/null || true

# 2. Create temp workspace
FIXTURE_BASE=$(mktemp -d /tmp/cmm-test-monorepo-XXXXXX)
BARE_REPOS="$FIXTURE_BASE/_bare"
mkdir -p "$BARE_REPOS"

# 3. Create bare repos (used as submodule origins)
git init --bare "$BARE_REPOS/vendor-core.git" -q
git init --bare "$BARE_REPOS/apps-alpha.git" -q
git init --bare "$BARE_REPOS/apps-beta.git" -q
git init --bare "$BARE_REPOS/shared-lib.git" -q

# 4. Seed bare repos with an initial commit
_seed_bare() {
    local bare_path="$1" name="$2"
    local tmp_clone
    tmp_clone=$(mktemp -d)
    git clone "$bare_path" "$tmp_clone/$name" -q
    echo "# $name" > "$tmp_clone/$name/README.md"
    git -C "$tmp_clone/$name" add README.md
    git -C "$tmp_clone/$name" -c user.email="test@test" -c user.name="Test" commit -m "init $name" -q
    git -C "$tmp_clone/$name" push origin HEAD:main -q
    rm -rf "$tmp_clone"
}
_seed_bare "$BARE_REPOS/vendor-core.git" "vendor-core"
_seed_bare "$BARE_REPOS/apps-alpha.git" "apps-alpha"
_seed_bare "$BARE_REPOS/apps-beta.git" "apps-beta"
_seed_bare "$BARE_REPOS/shared-lib.git" "shared-lib"

# 5. Build apps/alpha with nested submodule
ALPHA_WORK=$(mktemp -d)
git clone "$BARE_REPOS/apps-alpha.git" "$ALPHA_WORK/apps-alpha" -q
git -C "$ALPHA_WORK/apps-alpha" -c protocol.file.allow=always submodule add -q "file://$BARE_REPOS/vendor-core.git" vendor/core
git -C "$ALPHA_WORK/apps-alpha" -c user.email="test@test" -c user.name="Test" commit -m "add vendor/core submodule" -q
git -C "$ALPHA_WORK/apps-alpha" push origin HEAD:main -q
rm -rf "$ALPHA_WORK"

# 6. Build monorepo root with all submodules
MONO_ROOT="$FIXTURE_BASE/cmm-test-monorepo"
mkdir -p "$MONO_ROOT"
git -C "$MONO_ROOT" init -q
git -C "$MONO_ROOT" -c user.email="test@test" -c user.name="Test" commit --allow-empty -m "init monorepo" -q
git -C "$MONO_ROOT" -c protocol.file.allow=always submodule add -q "file://$BARE_REPOS/apps-alpha.git" apps/alpha
git -C "$MONO_ROOT" -c protocol.file.allow=always submodule add -q "file://$BARE_REPOS/apps-beta.git" apps/beta
git -C "$MONO_ROOT" -c protocol.file.allow=always submodule add -q "file://$BARE_REPOS/shared-lib.git" shared-lib
git -C "$MONO_ROOT" -c user.email="test@test" -c user.name="Test" commit -m "add submodules" -q

# 7. Initialize nested submodule inside apps/alpha
git -C "$MONO_ROOT" -c protocol.file.allow=always submodule update --init --recursive -q

# 8. Export and optionally print
export CMM_TEST_MONOREPO_ROOT="$MONO_ROOT"

# teardown_test_monorepo — removes the fixture created by this script.
# Call from test scripts after all tests complete.
teardown_test_monorepo() {
    if [ -n "$CMM_TEST_MONOREPO_ROOT" ]; then
        local base
        base="$(dirname "$CMM_TEST_MONOREPO_ROOT")"
        rm -rf "$base" 2>/dev/null || true
        unset CMM_TEST_MONOREPO_ROOT
    fi
}
export -f teardown_test_monorepo

# When run directly (not sourced), print the path
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "$CMM_TEST_MONOREPO_ROOT"
fi
