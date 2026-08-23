#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_single_release_producer.sh
#
# Establishes, by evidence rather than inference, that release-please has a
# single producer: the GitHub mirror. The canonical origin (Forgejo) must not
# run release-please, otherwise two producers would race over the same tags.
#
# The check is split in two:
#   - configuration: exactly one workflow invokes release-please-action, it is
#     gated to github.com, and Forgejo has no release producer.
#   - runtime: the git history contains a real release-please release commit
#     (authored by github-actions[bot] with subject "chore(main): release …"),
#     which proves the action actually ran on GitHub rather than only being
#     configured to.
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RP_WORKFLOW="${REPO_ROOT}/.github/workflows/release-please.yml"
GITHUB_WF_DIR="${REPO_ROOT}/.github/workflows"
FORGEJO_WF_DIR="${REPO_ROOT}/.forgejo/workflows"

failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }

# --- 1. the release-please workflow exists -------------------------------
if [ -f "$RP_WORKFLOW" ]; then
    pass "release-please workflow exists (.github/workflows/release-please.yml)"
else
    fail "release-please workflow missing (.github/workflows/release-please.yml)"
fi

# --- 2. exactly one workflow invokes release-please-action ---------------
count=$(grep -rl "release-please-action" "$GITHUB_WF_DIR" 2>/dev/null | wc -l | tr -d ' ' || true)
if [ "$count" -eq 1 ]; then
    pass "exactly one workflow invokes release-please-action ($count)"
else
    fail "expected exactly 1 workflow to invoke release-please-action, found $count"
fi

# --- 3. the release-please job is gated to the GitHub mirror --------------
if grep -q "github.server_url == 'https://github.com'" "$RP_WORKFLOW"; then
    pass "release-please workflow is gated to github.com (Forgejo skips it)"
else
    fail "release-please workflow is NOT gated to github.com"
fi

# --- 4. Forgejo must not be a second release producer --------------------
count=$(grep -rl "release-please" "$FORGEJO_WF_DIR" 2>/dev/null | wc -l | tr -d ' ' || true)
if [ "$count" -eq 0 ]; then
    pass "no Forgejo workflow references release-please (single producer)"
else
    fail "Forgejo workflow(s) reference release-please: $count"
fi

# --- 5. evidence release-please actually ran on the mirror ---------------
# `grep -q` under `pipefail` may kill git log with SIGPIPE on an early match;
# capture output first, then test the line count.
release_lines="$(git -C "$REPO_ROOT" log --all --format='%an|%s' | grep 'github-actions\[bot\]|chore(main): release' || true)"
if [ -n "$release_lines" ]; then
    pass "git history shows release-please release commits (github-actions[bot], 'chore(main): release')"
else
    fail "no release-please release commit found in git history"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "single release producer verified: $failures failure(s)"
    exit 0
else
    echo "single release producer NOT verified: $failures failure(s)"
    exit 1
fi
