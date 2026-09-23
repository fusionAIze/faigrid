#!/usr/bin/env bats
# ==============================================================================
# fusionAIze Grid - Tenant substrate preflight (VT-003)
# ==============================================================================
# Handover clause 5: both external tenant networks must be ready BEFORE a tenant
# workload spawns. The three criteria and how each is measured:
#
#   C1  with either network absent the preflight refuses BY NAME and spawns
#       nothing.
#   C2  with both present but unhealthy it refuses. What counts as unhealthy is
#       the definition in core/tenant/preflight.sh (faigrid_net_readiness_reason)
#       - this test constructs a present-but-unhealthy network and then asks the
#       CODE to classify it; it does not carry its own copy of the definition.
#   C3  the refusal precedes any tenant container creation, proven by a
#       `docker ps -a` snapshot comparison before and after the refusal.
#
# C3 uses `docker ps -a`, not `docker ps`: a container that is created and then
# exited would be invisible to `docker ps` and would still fail criterion 3.
# The snapshot projects ID, Names and Image - NOT Status - so a running
# container's uptime ticking over cannot produce a false difference.
#
# The snapshot is restricted to the tenant-container namespace
# (FAIGRID_TENANT_CONTAINER_PREFIX) that the guarded start is the only producer
# of. A daemon-wide comparison is unsafe here: the daemon is shared with the
# sibling lane VT-005, whose own probes (e.g. `vtt-listen`, and auto-named
# `docker run` containers) appear and disappear mid-run and would be misread as
# this refusal having spawned a tenant. The scoping never hides a container the
# refusal path itself could create: that path names every container it starts
# under the prefix, passed straight through to `docker run`.
#
# The library path is overridable with FAIGRID_PREFLIGHT_LIB so the red proof
# can run this very file against a guard-less copy of the library; the default
# is the real file under test.
# ==============================================================================

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
NETWORKS_SH="${REPO_ROOT}/core/tenant/networks.sh"
PREFLIGHT_LIB="${FAIGRID_PREFLIGHT_LIB:-${REPO_ROOT}/core/tenant/preflight.sh}"
CONTROL_NET="faigrid_control_net"
INFERENCE_NET="faigrid_inference_net"
# The namespace the guarded start is the only producer of. Mirrors
# FAIGRID_TENANT_CONTAINER_PREFIX in core/tenant/preflight.sh.
TENANT_PREFIX="faigrid-tenant-"

TENANT_NAME=""
PSA_BEFORE=""

# `docker ps -a` restricted to the tenant namespace, reduced to state that is
# stable across a test run a few seconds long. Status/uptime is deliberately
# excluded; it changes without a container having been created. `--filter` is
# anchored with `^...` so the prefix cannot be satisfied by a substring.
_docker_psa_snapshot() {
    docker ps -a --filter "name=^${TENANT_PREFIX}" \
        --format '{{.ID}} {{.Names}} {{.Image}}' | sort
}

setup() {
    docker >/dev/null 2>&1 || skip "docker not available"
    # Under the contract prefix, so a container the refusal path might spawn is
    # inside the snapshot above even if it were created under a variant name.
    TENANT_NAME="${TENANT_PREFIX}vt003-${BATS_TEST_NUMBER:-0}-$$"

    PSA_BEFORE="${BATS_TEST_TMPDIR}/psa.before"

    source "$NETWORKS_SH"
    faigrid_networks_remove >/dev/null 2>&1 || true
    faigrid_networks_create >/dev/null 2>&1

    _docker_psa_snapshot > "$PSA_BEFORE"
}

teardown() {
    # The broken-state probe creates a real container; take it down and sweep only
    # THIS test's tenant namespace (vt003-). The prefix alone is shared with the
    # sibling lane, so sweeping all faigrid-tenant-* could remove a concurrent
    # lane's container and turn its failure into ours.
    docker rm -f "$TENANT_NAME" >/dev/null 2>&1 || true
    local n
    for n in $(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^faigrid-tenant-vt003-' || true); do
        docker rm -f "$n" >/dev/null 2>&1 || true
    done
    # Force-remove both names regardless of the faigrid label: C2 deliberately
    # hand-creates one without the label, which the contract-preserving remove
    # would (correctly) refuse to touch.
    docker network rm "$CONTROL_NET" "$INFERENCE_NET" >/dev/null 2>&1 || true
    faigrid_networks_remove >/dev/null 2>&1 || true
}

# Fails, naming whatever container appeared, if `docker ps -a` differs from the
# snapshot taken in setup. `$1` is a label for the after-snapshot file.
assert_psa_unchanged() {
    local tag="${1:-x}"
    local after="${BATS_TEST_TMPDIR}/psa.after.${tag}"
    local diff_file="${BATS_TEST_TMPDIR}/psa.diff.${tag}"
    _docker_psa_snapshot > "$after"
    if ! diff -u "$PSA_BEFORE" "$after" > "$diff_file"; then
        local created
        created="$(grep -E '^\+' "$diff_file" | grep -vE '^\+\+\+' | sed 's/^+//' || true)"
        fail "docker ps -a changed during a refusal that should have created nothing - a container was created: ${created}"
    fi
}

@test "C1: an absent inference network is refused BY NAME and nothing spawns" {
    source "$PREFLIGHT_LIB"
    docker network rm "$INFERENCE_NET" >/dev/null 2>&1 || true

    run tenant_preflight
    [ "$status" -ne 0 ]
    [[ "$output" == *"$INFERENCE_NET"* ]]
    [[ "$output" == *"missing"* ]]

    assert_psa_unchanged "c1"
}

@test "C1b: an absent control network is refused BY NAME too" {
    source "$PREFLIGHT_LIB"
    docker network rm "$CONTROL_NET" >/dev/null 2>&1 || true

    run tenant_preflight
    [ "$status" -ne 0 ]
    [[ "$output" == *"$CONTROL_NET"* ]]
    [[ "$output" == *"missing"* ]]

    assert_psa_unchanged "c1b"
}

@test "C2: both present but unhealthy is refused by the check's own definition" {
    source "$PREFLIGHT_LIB"

    # Present and a bridge, but NOT the substrate VT-002 provisions: it carries
    # no faigrid creator label. Whether that counts as unhealthy is decided by
    # the library, not by this test.
    docker network rm "$CONTROL_NET" >/dev/null 2>&1 || true
    run docker network create --driver bridge "$CONTROL_NET"
    [ "$status" -eq 0 ]

    # The network exists (this is not the absent case) ...
    run faigrid_net_exists "$CONTROL_NET"
    [ "$status" -eq 0 ]

    # ... and the check classifies it as unhealthy.
    run faigrid_net_readiness_reason "$CONTROL_NET"
    [ -n "$output" ]

    run tenant_preflight
    [ "$status" -ne 0 ]
    [[ "$output" == *"$CONTROL_NET"* ]]
    [[ "$output" == *"unhealthy"* ]]

    assert_psa_unchanged "c2"
}

@test "C3: the refusal precedes any tenant container creation (docker ps -a)" {
    source "$PREFLIGHT_LIB"
    docker network rm "$INFERENCE_NET" >/dev/null 2>&1 || true

    run tenant_start "$TENANT_NAME"
    local start_status="$status"
    local start_output="$output"

    # Criterion 3 first: the evidence is the `docker ps -a` diff. In the broken
    # state (guard removed) tenant_start reaches `docker run`; this assertion
    # then fails and names the created container.
    assert_psa_unchanged "c3"

    [ "$start_status" -ne 0 ]
    [[ "$start_output" == *"$INFERENCE_NET"* ]]
}
