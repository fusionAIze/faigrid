#!/usr/bin/env bats
# ==============================================================================
# fusionAIze Grid - Preflight against the live substrate (GO-005)
# ==============================================================================
# core/tenant/preflight.sh has never run against the live substrate. This file
# proves, against the nexus-core docker daemon, that:
#
#   C1  preflight.sh returns success when both tenant networks are present and
#       healthy on the live node,
#   C2  with one tenant network removed, preflight refuses BY NAME and creates
#       nothing, proven by an unchanged docker ps -a,
#   C3  the refusal precedes any tenant container creation, shown by the absence
#       of any container with the tenant prefix.
#
# How the proof works
# -------------------
# The test runs the local core/tenant/preflight.sh (which sources networks.sh)
# against the nexus-core docker daemon via DOCKER_HOST=ssh://<host>.
#
# C2 removes faigrid_inference_net (disconnecting faigate first), runs preflight,
# captures the refusal (network named, exit non-zero), captures docker ps -a to
# prove no container was created, then restores the network and reconnects
# faigate. compose_grid_net is never touched.
#
# C3 is proven by the docker ps -a comparison: identical before and after the
# refusal, and no container with the tenant prefix was ever present.
#
# RED PROOF: the C2+C3 test asserts non-zero exit from preflight with the absent
# network. If preflight were to pass with a network missing, the assertion
# fails and the suite exits 1.
#
# Transport
# ---------
# The checks run against the docker daemon on nexus-core, addressed with
# `docker -H ssh://<host>`. Off that host the file skips rather than failing.
# ==============================================================================

fail() { printf 'ASSERTION FAILED: %s\n' "$*" >&2; return 1; }

NEXUS_HOST="${NEXUS_HOST:-nexus-core}"

CONTROL_NET="faigrid_control_net"
INFERENCE_NET="faigrid_inference_net"
COMPOSE_NET="compose_grid_net"
TENANT_PREFIX="faigrid-tenant-"

PREFLIGHT_SCRIPT="${BATS_TEST_DIRNAME}/../../core/tenant/preflight.sh"

PSA_FORMAT='{{.ID}} {{.Names}} {{.Image}}'
_psa_snapshot() { rdocker ps -a --format "$PSA_FORMAT" | sort; }

rdocker() { docker -H "ssh://${NEXUS_HOST}" "$@"; }

_remote_available() { rdocker version >/dev/null 2>&1; }

# Track whether the inference network was removed, for teardown recovery
_NET_REMOVED=""

setup() {
    command -v docker >/dev/null 2>&1 || skip "docker CLI not available"
    _remote_available || skip "docker daemon on '${NEXUS_HOST}' not reachable (set NEXUS_HOST)"
}

teardown() {
    if [[ "$_NET_REMOVED" == "true" ]]; then
        _NET_REMOVED=""
        if ! rdocker network inspect "$INFERENCE_NET" >/dev/null 2>&1; then
            rdocker network create \
                --driver bridge \
                --label com.fusionaize.faigrid.creator=faigrid \
                "$INFERENCE_NET" >/dev/null 2>&1 || true
        fi
        local attached
        attached="$(rdocker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' faigate 2>/dev/null || true)"
        if [[ "$attached" != *"$INFERENCE_NET"* ]]; then
            rdocker network connect "$INFERENCE_NET" faigate >/dev/null 2>&1 || true
        fi
    fi
}

@test "C1: preflight.sh returns success against the live substrate" {
    run env DOCKER_HOST="ssh://${NEXUS_HOST}" bash "$PREFLIGHT_SCRIPT" check
    [ "$status" -eq 0 ] || fail "preflight failed against live substrate: ${output}"
    [[ "$output" == *"OK"* ]] || fail "preflight output does not indicate OK: ${output}"
    echo "# preflight OK on ${NEXUS_HOST}: ${output}" >&3
}

@test "C2+C3: with one tenant network removed, preflight refuses BY NAME, creates nothing" {
    local psa_before
    psa_before="$(_psa_snapshot)"

    # Never remove compose_grid_net
    rdocker network inspect "$COMPOSE_NET" >/dev/null 2>&1 \
        || fail "compose_grid_net is missing - this test must never remove it"

    rdocker network inspect "$INFERENCE_NET" >/dev/null 2>&1 \
        || fail "${INFERENCE_NET} does not exist before the test - nothing to remove"

    # Disconnect faigate, then remove the network
    rdocker network disconnect "$INFERENCE_NET" faigate 2>/dev/null || true
    rdocker network rm "$INFERENCE_NET" >/dev/null 2>&1 \
        || fail "could not remove ${INFERENCE_NET}"

    _NET_REMOVED="true"

    if rdocker network inspect "$INFERENCE_NET" >/dev/null 2>&1; then
        fail "${INFERENCE_NET} still exists after docker network rm"
    fi

    # C2: preflight must refuse by name
    run env DOCKER_HOST="ssh://${NEXUS_HOST}" bash "$PREFLIGHT_SCRIPT" check
    [ "$status" -ne 0 ] \
        || fail "preflight PASSED with ${INFERENCE_NET} missing - should have refused (RED PROOF FAILED)"
    [[ "$output" == *"$INFERENCE_NET"* ]] \
        || fail "preflight did not name the missing network '${INFERENCE_NET}': ${output}"
    [[ "$output" == *"missing"* ]] \
        || fail "preflight did not say 'missing' for the absent network: ${output}"

    # C2: docker ps -a must be unchanged (no containers created)
    local psa_after_refusal
    psa_after_refusal="$(_psa_snapshot)"
    if [[ "$psa_before" != "$psa_after_refusal" ]]; then
        local diff_out
        diff_out="$(diff -u <(printf '%s\n' "$psa_before") <(printf '%s\n' "$psa_after_refusal") 2>/dev/null || true)"
        fail "docker ps -a changed during a refusal that should have created nothing: ${diff_out}"
    fi

    # C3: no tenant container ever existed - refusal preceded any creation
    local tenant_names
    tenant_names="$(rdocker ps -a --format '{{.Names}}' | grep -E "^${TENANT_PREFIX}" || true)"
    [[ -z "$tenant_names" ]] \
        || fail "tenant container(s) exist despite preflight refusal: ${tenant_names}"

    # Restore the network and reconnect faigate
    rdocker network create \
        --driver bridge \
        --label com.fusionaize.faigrid.creator=faigrid \
        "$INFERENCE_NET" >/dev/null 2>&1 \
        || fail "could not recreate ${INFERENCE_NET}"
    rdocker network connect "$INFERENCE_NET" faigate >/dev/null 2>&1 \
        || fail "could not reconnect faigate to ${INFERENCE_NET}"
    _NET_REMOVED=""

    local faigate_nets
    faigate_nets="$(rdocker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' faigate 2>/dev/null || true)"
    [[ "$faigate_nets" == *"$INFERENCE_NET"* ]] \
        || fail "faigate not reconnected to ${INFERENCE_NET}: ${faigate_nets}"

    # Verify the restored network passes preflight
    run env DOCKER_HOST="ssh://${NEXUS_HOST}" bash "$PREFLIGHT_SCRIPT" check
    [ "$status" -eq 0 ] \
        || fail "preflight still fails after restoring ${INFERENCE_NET}: ${output}"
    [[ "$output" == *"OK"* ]] \
        || fail "preflight output does not indicate OK after restore: ${output}"

    # Final: docker ps -a still identical to baseline
    local psa_final
    psa_final="$(_psa_snapshot)"
    if [[ "$psa_before" != "$psa_final" ]]; then
        local diff_final
        diff_final="$(diff -u <(printf '%s\n' "$psa_before") <(printf '%s\n' "$psa_final") 2>/dev/null || true)"
        fail "docker ps -a changed across the full C2+C3 test: ${diff_final}"
    fi

    echo "# C2: refused ${INFERENCE_NET} by name, no containers created, network restored" >&3
    echo "# C3: no tenant container (${TENANT_PREFIX}*) ever existed" >&3
}
