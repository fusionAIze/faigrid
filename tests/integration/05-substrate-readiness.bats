#!/usr/bin/env bats
# ==============================================================================
# fusionAIze Grid - Substrate readiness for veeona (VT-007)
# ==============================================================================
# Proves that the substrate is ready for veeona WITHOUT starting veeona:
#
#   C1  veeona's docker-compose.yml validates against the live substrate -- every
#       `external: true` network it declares resolves on the node.
#   C2  the validation starts no tenant workload: no veeona container appears in
#       `docker ps`, asserted rather than observed in passing.
#   C3  the written readiness report exists and names every handover clause with
#       met / not met / out of scope -- no clause left unaddressed.
#
# What "resolve" means here, and why it is NOT `docker compose config` alone
# ------------------------------------------------------------------------
# Measured on nexus-core 2026-09-24 with Docker Compose v5.0.2: `docker compose
# config` exits 0 even when a declared `external: true` network does not exist.
# Compose resolves the *name* from the file; it does not contact the daemon to
# assert the network is present. So a test that asserts only the config exit code
# is green on a substrate that is NOT ready -- exactly the failure this lane
# exists to catch.
#
# The resolvable proof is therefore: parse the external networks out of
# `docker compose config`, then `docker network inspect` each one. A missing
# network makes inspect exit non-zero and names it. This is read-only: no
# `up`, no `create`, no `--dry-run` (which pulls images).
#
# The red proof is a property of this test, not a separate always-green case:
# with one tenant network removed, C1 fails and names the unresolved network.
# Both runs (network absent -> 1, both present -> 0) are recorded with exit
# codes in LANE-REPORT.md. Set VEEONA_COMPOSE to point at veeona's file; the
# default is the operator-supplied path.
#
# Scoping: criterion 1 is about the LIVE substrate on nexus-core, not about
# whatever host happens to run CI. On any other host C1 has no target and is
# skipped, so a CI runner (which has no tenant networks) cannot turn an
# unavailable substrate into a red build. Set VEEONA_SUBSTRATE_HOST to the
# expected hostname; the check runs when `hostname` matches it.
# ==============================================================================

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
NETWORKS_SH="${REPO_ROOT}/core/tenant/networks.sh"
READINESS_DOC="${REPO_ROOT}/docs/reference/veeona-substrate-readiness.md"

# veeona's compose is veeona's file: supplied by the operator and never committed
# here. Overridable so the reviewer can point at their own checkout.
VEEONA_COMPOSE="${VEEONA_COMPOSE:-/Users/andrelange/Documents/repositories/forgejo/veeona/veeona/docker-compose.yml}"

# The host whose substrate criterion 1 is measured against. Off that host the
# resolution assertion is skipped: CI has no tenant networks and a missing
# substrate there is not a finding.
VEEONA_SUBSTRATE_HOST="${VEEONA_SUBSTRATE_HOST:-nexus-core}"

CONTROL_NET="faigrid_control_net"
INFERENCE_NET="faigrid_inference_net"

setup() {
    docker >/dev/null 2>&1 || skip "docker not available"
    [[ -f "$VEEONA_COMPOSE" ]] || skip "veeona's docker-compose.yml not present at ${VEEONA_COMPOSE}"
    command -v docker >/dev/null 2>&1 || skip "docker not available"
}

# Names of the networks veeona's compose declares as external. Parsed from the
# rendered config so it tracks whatever the file says, not a hard-coded list.
_external_networks() {
    docker compose -f "$VEEONA_COMPOSE" --profile all config 2>/dev/null \
        | awk '
            /^  [A-Za-z0-9_.-]+:$/ { cand=""; next }
            /^    name:[[:space:]]/ { cand=$2; next }
            /external:[[:space:]]*true/ { if (cand != "") print cand; cand=""; next }
        '
}

@test "C1: veeona's compose renders and every external network resolves on the substrate" {
    # Criterion 1 is about the live substrate. Off the target host this test has
    # no substrate to measure; skip rather than fail CI for an env it does not own.
    if [[ "$(hostname)" != "$VEEONA_SUBSTRATE_HOST" ]]; then
        skip "not on substrate host '${VEEONA_SUBSTRATE_HOST}' (is: $(hostname)); criterion 1 is measured there"
    fi

    # The file must at least parse as compose.
    run docker compose -f "$VEEONA_COMPOSE" --profile all config
    assert_success

    # It must declare exactly the two faigrid tenant networks as external.
    local ext
    ext="$(_external_networks)"
    [[ "$ext" == *"$CONTROL_NET"* ]]
    [[ "$ext" == *"$INFERENCE_NET"* ]]

    # And each one must actually exist on the live substrate. This is the
    # resolution proof; `config` alone does not make it.
    local net
    while IFS= read -r net; do
        [[ -n "$net" ]] || continue
        run docker network inspect "$net"
        if [[ "$status" -ne 0 ]]; then
            fail "external network '${net}' declared by veeona's compose does NOT resolve on the substrate (docker network inspect exit ${status})"
        fi
    done <<<"$ext"
}

@test "C2: validation starts no tenant workload -- docker ps asserts no veeona container" {
    # Asserted, not observed: the count of veeona-named running containers must be
    # exactly zero. `grep -c` with no match exits 1, so guard it with `|| true`.
    local veeona_containers
    veeona_containers="$(docker ps --format '{{.Names}}' | grep -c 'veeona' || true)"
    [[ "$veeona_containers" -eq 0 ]]

    # Non-vacuous guard: docker ps actually reported the host's containers, so a
    # broken/denied docker ps cannot make the zero above meaningless.
    run docker ps --format '{{.Names}}'
    assert_success

    # And veeona's *own* declared service names must not be running either, by
    # container_name, which is what would appear if veeona had been started.
    local name
    for name in veeona-grid-edge veeona-z0-control veeona-z1-research \
        veeona-z2-production veeona-knowledge-graph; do
        if docker ps --format '{{.Names}}' | grep -qx "$name"; then
            fail "tenant workload '${name}' is RUNNING -- veeona was started"
        fi
    done
}

@test "C3: the readiness report names every handover clause with a verdict" {
    [[ -f "$READINESS_DOC" ]]

    run cat "$READINESS_DOC"
    assert_success

    # Every clause row must carry one of the three permitted verdicts.
    local clauses
    clauses="$(grep -c '^| HC-' "$READINESS_DOC" || true)"
    [[ "$clauses" -ge 5 ]]

    local verdicts
    verdicts="$(grep -c 'met\|not met\|out of scope' "$READINESS_DOC" || true)"
    [[ "$verdicts" -ge "$clauses" ]]

    # No clause may be left unaddressed: the count of clause rows must equal the
    # count of rows that also carry a verdict token.
    local named
    named="$(grep '^| HC-' "$READINESS_DOC" | grep -c 'met\|out of scope' || true)"
    [[ "$named" -eq "$clauses" ]]
}
