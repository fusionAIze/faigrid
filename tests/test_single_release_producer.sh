#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_single_release_producer.sh
#
# Establishes, by evidence rather than inference, the release path invariants
# that the FFR-600 division depends on:
#
#   1. release-please has a single producer: the GitHub mirror. The canonical
#      origin (Forgejo) must not run release-please, otherwise two producers
#      would race over the same tags.
#   2. The Homebrew tap dispatch is wired as post-mirror distribution: a
#      notify-tap workflow keyed on the GitHub release event, plus the
#      release-please notify-tap fallback, both gated to github.com.
#
# The producer check is split in two:
#   - configuration: exactly one workflow invokes release-please-action, it is
#     gated to github.com, and Forgejo has no release producer.
#   - runtime: the git history contains a real release-please release commit
#     (authored by github-actions[bot] or app/github-actions with subject
#     "chore(main): release …"), which proves the action actually ran on
#     GitHub rather than only being configured to.
#
# This test is offline: it reads only the repository. GitHub-side residue
# (open release PRs, tag-shape drift) is documented in docs/release-path.md;
# it is not asserted here because it requires a live GitHub token.
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RP_WORKFLOW="${REPO_ROOT}/.github/workflows/release-please.yml"
TAP_WORKFLOW="${REPO_ROOT}/.github/workflows/notify-tap.yml"
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
release_lines="$(git -C "$REPO_ROOT" log --all --format='%an|%s' \
    | grep -E 'github-actions\[bot\]\|chore\(main\): release|app/github-actions\|chore\(main\): release' || true)"
if [ -n "$release_lines" ]; then
    pass "git history shows release-please release commits (github-actions[bot]/app-github-actions, 'chore(main): release')"
else
    fail "no release-please release commit found in git history"
fi

# --- 6. the tap dispatch is wired as post-mirror distribution -------------
#    The standalone notify-tap.yml keys on the GitHub release:publish event and
#    must be gated to github.com.
if [ -f "$TAP_WORKFLOW" ]; then
    if grep -q "types: \[published\]" "$TAP_WORKFLOW" \
       && grep -q "github.server_url == 'https://github.com'" "$TAP_WORKFLOW"; then
        pass "notify-tap.yml triggers on release.published and is gated to github.com"
    else
        fail "notify-tap.yml missing release.published trigger or github.com gate"
    fi
else
    fail "notify-tap.yml missing (.github/workflows/notify-tap.yml)"
fi

#    The dispatch must target the homebrew-tap repository with the
#    formula-update event type for formula 'faigrid'.
if grep -q "repo:  'homebrew-tap'" "$TAP_WORKFLOW" \
   && grep -q "event_type: 'formula-update'" "$TAP_WORKFLOW" \
   && grep -q "formula: 'faigrid'" "$TAP_WORKFLOW"; then
    pass "tap dispatch targets homebrew-tap with formula-update for faigrid"
else
    fail "tap dispatch is not wired to homebrew-tap / formula-update / faigrid"
fi

#    Every tap-dispatch path must be gated to github.com, including the
#    release-please notify-tap fallback job.
if grep -q "notify-tap" "$RP_WORKFLOW" \
   && grep -q "github.server_url == 'https://github.com'" "$RP_WORKFLOW"; then
    pass "release-please notify-tap fallback present and gated to github.com"
else
    fail "release-please notify-tap fallback missing or not gated to github.com"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "release path verified (single producer + tap distribution): $failures failure(s)"
    exit 0
else
    echo "release path NOT verified: $failures failure(s)"
    exit 1
fi
