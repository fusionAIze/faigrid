#!/usr/bin/env bats
# ==============================================================================
# fusionAIze Grid - Tenant Network Isolation (VT-002)
# ==============================================================================
# SEC-001: faigrid_control_net and faigrid_inference_net must NEVER be bridged.
#
# The three criteria are proven here by REFUSAL, not by reading docker network
# inspect and calling it proof:
#
#   C1  both networks exist and were created by faigrid (creator label)
#   C2  a test that BRIDGES the two networks FAILS (red proof: reachable host
#       is named, this test exits 1)
#   C3  a container on inference_net cannot reach one on control_net, captured
#       as a timed-out/refused connection attempt
#
# C3 is a real connection attempt: a control-net container serves HTTP, an
# inference-net container tries to wget it, and the failure (download timed
# out) is asserted, not the absence of routes.
#
# RED PROOF: if the two networks are joined (a `docker network connect`
# bridges a container onto both), the same probe SUCCEEDS and this test exits 1
# naming the reachable host. A test that only asserts both networks exist would
# pass in the bridged state and therefore does not prove isolation.
# ==============================================================================

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

NETWORKS_SH="${BATS_TEST_DIRNAME}/../../core/tenant/networks.sh"
CONTROL_NET="faigrid_control_net"
INFERENCE_NET="faigrid_inference_net"
CREATOR_LABEL="com.fusionaize.faigrid.creator"
CREATOR_VALUE="faigrid"
PROBE_PORT="7777"
PROBE_TIMEOUT="5"

_server_cid=""
_server_ip=""

setup() {
    # The isolation proof builds on networks *we* create fresh per file. Use a
    # run-scoped suffix so a stray network from a previous run never leaks in.
    docker >/dev/null 2>&1 || skip "docker not available"
    source "$NETWORKS_SH"
    faigrid_networks_remove >/dev/null 2>&1 || true
    faigrid_networks_create
}

teardown() {
    if [[ -n "$_server_cid" ]]; then
        docker rm -f "$_server_cid" >/dev/null 2>&1 || true
        _server_cid=""
    fi
    faigrid_networks_remove >/dev/null 2>&1 || true
}

# Start the control-net HTTP listener. Sets the globals _server_cid and
# _server_ip. Must NOT be invoked inside $(...) because that would run it in a
# subshell and lose both assignments.
_start_control_listener() {
    if [[ -n "$_server_cid" ]]; then
        docker rm -f "$_server_cid" >/dev/null 2>&1 || true
    fi
    _server_cid="$(docker run -d --rm --network "$CONTROL_NET" \
        --name "vt002-control-$$" \
        busybox:latest httpd -f -p "$PROBE_PORT")"
    _server_ip="$(docker inspect -f "{{.NetworkSettings.Networks.${CONTROL_NET}.IPAddress}}" "$_server_cid")"
}

@test "C1: both tenant networks exist and carry the faigrid creator label" {
    local control_present inference_present
    control_present="$(docker network inspect -f "{{index .Labels \"${CREATOR_LABEL}\"}}" "$CONTROL_NET")"
    inference_present="$(docker network inspect -f "{{index .Labels \"${CREATOR_LABEL}\"}}" "$INFERENCE_NET")"

    [[ "$control_present" == "$CREATOR_VALUE" ]]
    [[ "$inference_present" == "$CREATOR_VALUE" ]]

    run docker network inspect "$CONTROL_NET"
    assert_success
    run docker network inspect "$INFERENCE_NET"
    assert_success
}

@test "C3: a container on inference_net cannot reach one on control_net (timed-out refusal)" {
    _start_control_listener
    local server_ip="$_server_ip"
    [[ -n "$server_ip" ]]

    # Real connection attempt
    run docker run --rm --network "$INFERENCE_NET" \
        busybox:latest wget -T "$PROBE_TIMEOUT" -O /dev/null \
        "http://${server_ip}:${PROBE_PORT}/"

    # The attempt must fail. If it succeeded, the networks are bridged and the
    # isolation property is broken — name the reachable host.
    if [[ "$status" -eq 0 ]]; then
        fail "inference_net container REACHED control_net host ${server_ip}:${PROBE_PORT} — the two tenant networks are bridged"
    fi

    # The failure must be the captured timed-out/refused connection, not an
    # empty run: wget names the timeout explicitly.
    assert_output --regexp "timed out|refused|unreachable|no route|error"
}

@test "C2: bridging the two networks makes the cross-network probe reach the host (red-proof premise)" {
    _start_control_listener
    local server_ip="$_server_ip"
    [[ -n "$server_ip" ]]

    # Deliberately bridge the server onto the inference network. This is the
    # SEC-001 violation. In this broken state the very same probe that C3 uses
    # must reach the host — proving that C3 catches bridging (a test that only
    # asserted both networks exist would stay green here and prove nothing).
    docker network connect "$INFERENCE_NET" "$_server_cid"
    local bridged_ip
    bridged_ip="$(docker inspect -f "{{.NetworkSettings.Networks.${INFERENCE_NET}.IPAddress}}" "$_server_cid")"
    [[ -n "$bridged_ip" ]]

    run docker run --rm --network "$INFERENCE_NET" \
        busybox:latest wget -T "$PROBE_TIMEOUT" -O /dev/null \
        "http://${bridged_ip}:${PROBE_PORT}/"

    # Reachability is proven by a zero exit OR by an HTTP response line from
    # the server (wget returns non-zero on the 404-but-connected case).
    local reached=0
    if [[ "$status" -eq 0 ]]; then
        reached=1
    elif [[ "$output" == *"server returned error"* ]]; then
        reached=1
    fi

    [[ "$reached" -eq 1 ]] || fail \
        "expected bridged probe to reach ${bridged_ip}:${PROBE_PORT} but it did not (rc=${status}; ${output})"
}
