#!/usr/bin/env bats
# ==============================================================================
# fusionAIze Grid - Tenant Network Isolation (VT-002)
# ==============================================================================
# SEC-001: faigrid_control_net and faigrid_inference_net must NEVER be bridged.
#
# The isolation property is proven by a real, refused connection attempt. A
# `docker network inspect` reading is used only for criterion 1 (the creator
# label), never as isolation evidence.
#
# How the probe tells REACHED from NOT REACHED
# --------------------------------------------
# The control listener serves a real document root whose index.html contains a
# unique sentinel, so a probe that REACHES the host gets HTTP 200, the sentinel
# body, and wget exit 0. A probe that cannot reach the host gets a connect
# timeout (or refusal) and wget exit 1. The two cases share no exit code and no
# output string.
#
# This matters: `busybox httpd` with no document root answers `/` with 404, so a
# *successful* connection also yields wget exit 1 — indistinguishable from a
# timeout by exit code alone. The previous version keyed on exit code and on a
# regex that included the bare word "error", so it matched the reached case's
# "server returned error" and stayed green while the networks were bridged. The
# sentinel removes that ambiguity.
#
# Tests and criteria
# ------------------
#   C1  both tenant networks exist and were created by faigrid (creator label)
#   C3  a container on inference_net cannot reach one on control_net, captured
#       as a refused/timed-out connection. C3 also runs an in-test positive
#       control (the same listener, reached from its own network) so that a
#       dead listener can never read as a successful refusal. This is the
#       bridge detector: if a path exists, the probe reaches the sentinel and
#       C3 fails with the reachable host named, so the file exits 1.
#
# Criterion 2 ("a test that bridges the two networks FAILS") is the red-proof
# property of C3, not a separate always-green test: with the networks bridged,
# C3 fails and the suite exits 1. Both runs (bridged -> 1, separated -> 0) are
# recorded with their exit codes in LANE-REPORT.md.
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
# Only a probe that actually reached the listener can see this body.
SENTINEL="VT002_CONTROL_SENTINEL_9f3a"
# Failure strings a NOT-REACHED probe emits. Kept narrow on purpose: a bare
# "error" would also match wget's "server returned error", which is what a
# REACHED host answers with on an HTTP error — the exact confusion that made the
# previous assertion unsound.
UNREACHED_RE="timed out|refused|unreachable|no route|bad address|can't connect"

_server_cid=""
_server_ip=""
_server_name="vt002-control-$$"

setup() {
    # The isolation proof builds on networks *we* create fresh per file.
    docker >/dev/null 2>&1 || skip "docker not available"
    source "$NETWORKS_SH"
    faigrid_networks_remove >/dev/null 2>&1 || true
    faigrid_networks_create
}

teardown() {
    docker rm -f "$_server_name" >/dev/null 2>&1 || true
    if [[ -n "$_server_cid" ]]; then
        docker rm -f "$_server_cid" >/dev/null 2>&1 || true
        _server_cid=""
    fi
    faigrid_networks_remove >/dev/null 2>&1 || true
}

# Start the control-net HTTP listener on a real document root. Sets the globals
# _server_cid and _server_ip. Must NOT be invoked inside $(...) because that
# would run it in a subshell and lose both assignments.
_start_control_listener() {
    docker rm -f "$_server_name" >/dev/null 2>&1 || true
    if [[ -n "$_server_cid" ]]; then
        docker rm -f "$_server_cid" >/dev/null 2>&1 || true
    fi
    _server_cid="$(docker run -d --rm --network "$CONTROL_NET" \
        --name "$_server_name" \
        busybox:latest \
        sh -c "mkdir -p /www && printf '%s\n' '${SENTINEL}' > /www/index.html && exec httpd -f -p ${PROBE_PORT} -h /www")"
    _server_ip="$(docker inspect -f "{{.NetworkSettings.Networks.${CONTROL_NET}.IPAddress}}" "$_server_cid" 2>/dev/null || true)"

    # Wait until the listener answers 200 on its own network, so a later refusal
    # is never mistaken for a listener that simply had not started yet.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if docker run --rm --network "$CONTROL_NET" busybox:latest \
            wget -q -T 2 -O /dev/null "http://${_server_ip}:${PROBE_PORT}/" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 0
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

@test "C3: a container on inference_net cannot reach one on control_net (refused/timed-out)" {
    _start_control_listener
    local server_ip="$_server_ip"
    [[ -n "$server_ip" ]]

    # Positive control: the very same listener, reached from its own network,
    # MUST answer with the sentinel. Without this a dead listener would make the
    # refusal below vacuously true.
    run docker run --rm --network "$CONTROL_NET" \
        busybox:latest wget -T "$PROBE_TIMEOUT" -O - \
        "http://${server_ip}:${PROBE_PORT}/"
    assert_success
    assert_output --partial "$SENTINEL"

    # Real connection attempt from the untrusted inference plane.
    run docker run --rm --network "$INFERENCE_NET" \
        busybox:latest wget -T "$PROBE_TIMEOUT" -O - \
        "http://${server_ip}:${PROBE_PORT}/"

    # REACHED iff the probe got the sentinel, a zero exit, or an HTTP error line
    # from the server. Any of these means a path exists and SEC-001 is broken.
    if [[ "$status" -eq 0 ]] \
        || [[ "$output" == *"$SENTINEL"* ]] \
        || [[ "$output" == *"server returned error"* ]]; then
        fail "inference_net container REACHED control_net host ${server_ip}:${PROBE_PORT} — the two tenant networks are bridged"
    fi

    # The failure must be the captured connection refusal/timeout, not an empty
    # run. The pattern deliberately excludes the bare word "error".
    assert_output --regexp "$UNREACHED_RE"
}
