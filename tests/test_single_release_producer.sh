#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_single_release_producer.sh
#
# Encodes the FFR-600-2 target-state release-path invariants:
#
#   1. The GitHub mirror has NO release producer. release-please is gone:
#      `.github/workflows/release-please.yml` no longer exists, no workflow in
#      `.github/workflows/` references release-please-action, and the
#      release-please config files are absent. Faigrid produces releases on
#      Forgejo (ops-engine), not on the mirror.
#   2. Forgejo (`.forgejo/workflows/`) has no release-please producer either;
#      mirror.yml is push-only and the release producer is the ops-engine
#      workflow `.forgejo/workflows/forgejo-release.yml`.
#   3. The Forgejo producer exists and carries ops-engine's two-job shape: a
#      `gate` job and a `release` job with `needs: gate`, pinned to v3.4.2 and
#      reading the committed `.ops.yaml` / `.release-title-prefix`.
#   4. The Homebrew tap dispatch is post-mirror distribution: notify-tap.yml
#      triggers on the push of a `v*` tag (what mirror.yml copies from Forgejo),
#      is gated to github.com, and does NOT depend on any release-please job.
#      The dispatch targets homebrew-tap with formula-update for faigrid.
#
# This test is offline: it reads only the repository and asserts the target
# state. Historical evidence (the past release-please runs) is documented in
# docs/release-path.md; it is not asserted here because the target state has
# no release-please producer.
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RP_WORKFLOW="${REPO_ROOT}/.github/workflows/release-please.yml"
TAP_WORKFLOW="${REPO_ROOT}/.github/workflows/notify-tap.yml"
RP_CONFIG="${REPO_ROOT}/release-please-config.json"
RP_MANIFEST="${REPO_ROOT}/.release-please-manifest.json"
GITHUB_WF_DIR="${REPO_ROOT}/.github/workflows"
FORGEJO_WF_DIR="${REPO_ROOT}/.forgejo/workflows"
FP_WORKFLOW="${FORGEJO_WF_DIR}/forgejo-release.yml"

failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }

# --- 1. the release-please workflow must NOT exist -------------------------
if [ -f "$RP_WORKFLOW" ]; then
    fail "release-please workflow still present (.github/workflows/release-please.yml) — mirror must not produce releases"
else
    pass "release-please workflow removed (no mirror release producer)"
fi

# --- 2. no workflow invokes release-please-action --------------------------
count=$(grep -rl "release-please-action" "$GITHUB_WF_DIR" 2>/dev/null | wc -l | tr -d ' ' || true)
if [ "$count" -eq 0 ]; then
    pass "no workflow in .github/workflows references release-please-action ($count)"
else
    fail "expected 0 workflows to reference release-please-action, found $count"
fi

# --- 3. the release-please config files are gone ---------------------------
if [ -f "$RP_CONFIG" ] || [ -f "$RP_MANIFEST" ]; then
    fail "release-please config/manifest still present (dead configuration)"
else
    pass "release-please config and manifest removed"
fi

# --- 4. Forgejo must not be a release-please producer ----------------------
count=$(grep -rl "release-please" "$FORGEJO_WF_DIR" 2>/dev/null | wc -l | tr -d ' ' || true)
if [ "$count" -eq 0 ]; then
    pass "no Forgejo workflow references release-please (producer is the ops-engine, not release-please)"
else
    fail "Forgejo workflow(s) reference release-please: $count"
fi

# --- 5. the Forgejo producer exists --------------------------------
if [ -f "$FP_WORKFLOW" ]; then
    pass "Forgejo producer present (.forgejo/workflows/forgejo-release.yml)"
else
    fail "Forgejo producer missing (.forgejo/workflows/forgejo-release.yml)"
fi

# --- 6. the producer carries the two-job gate -> release split ---------------
if grep -q '^\s*needs:\s*gate' "$FP_WORKFLOW"; then
    pass "release job carries 'needs: gate' (a failing gate stops publication)"
else
    fail "release job does not depend on gate (3.4.2's two-job split missing)"
fi

# --- 7. the producer is pinned to ops-engine v3.4.2 --------------------------
if grep -q 'v3\.4\.2' "$FP_WORKFLOW"; then
    pass "producer pins ops-engine v3.4.2"
else
    fail "producer does not pin ops-engine v3.4.2"
fi

# --- 8. the tap dispatch is wired to the mirrored tag push ------------------
if [ -f "$TAP_WORKFLOW" ]; then
    if grep -q 'tags:' "$TAP_WORKFLOW" \
       && grep -q '"v\*"' "$TAP_WORKFLOW" \
       && grep -q "github.server_url == 'https://github.com'" "$TAP_WORKFLOW"; then
        pass "notify-tap.yml triggers on v* tag push and is gated to github.com"
    else
        fail "notify-tap.yml missing v* tag trigger or github.com gate"
    fi
else
    fail "notify-tap.yml missing (.github/workflows/notify-tap.yml)"
fi

# --- 9. the tap dispatch must not depend on release-please ------------------
#      (grep for a real `needs:` dependency or an action reference, not for
#      the word in a comment, which is legitimate documentation)
if grep -Eq 'needs:.*release-please|release-please-action' "$TAP_WORKFLOW"; then
    fail "notify-tap.yml depends on release-please (needs:/action reference found)"
else
    pass "notify-tap.yml has no release-please dependency"
fi

# --- 10. the dispatch targets homebrew-tap for formula faigrid ----------------
if grep -q "repo:  'homebrew-tap'" "$TAP_WORKFLOW" \
   && grep -q "event_type: 'formula-update'" "$TAP_WORKFLOW" \
   && grep -q "formula: 'faigrid'" "$TAP_WORKFLOW"; then
    pass "tap dispatch targets homebrew-tap with formula-update for faigrid"
else
    fail "tap dispatch is not wired to homebrew-tap / formula-update / faigrid"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "release path verified (Forgejo producer, mirror distribution only): $failures failure(s)"
    exit 0
else
    echo "release path NOT verified: $failures failure(s)"
    exit 1
fi
