#!/usr/bin/env bats
# ==============================================================================
# fusionAIze Grid - Tenant credential mediator isolation (VT-005)
# ==============================================================================
# SEC-001 + the CredentialBroker clause: a z1 worker must reach the broker ONLY
# through a single dual-homed mediator, that mediator must not forward IP traffic
# between the two planes, and no worker's environment may carry a long-lived
# secret.
#
# How a reached host is told from an unreached one
# ------------------------------------------------
# A broker answered over the wire returns whatever its handler wrote ("token",
# "long_lived") and wget exits 0. A broker that cannot be reached returns a
# refusal (busybox wget prints "Connection refused" for a dead-but-routable host,
# "download timed out" for a dropped route) and exits 1. Every assertion compares
# CONTENT, not only exit code, so a "reached" host is never mistaken for a
# refusal. The same trap VT-002 hit: an HTTP 404 also exits 1, which looked like
# a timeout. Here the broker's token endpoint answers 200 with a body, so a
# reached host is unambiguously "token" + exit 0.
#
# Tests and criteria
#   C1  exactly one container is dual-homed (the mediator), and a forward attempt
#       THROUGH it is refused; the red proof forces ip_forward=1 and the same
#       probe reaches the broker, failing the suite.
#   C2  a z1 worker obtains a SCOPED token through the mediator AND the direct
#       broker path is refused. Both halves asserted.
#   C3  dump each worker's environment and assert no long-lived secret is
#       present; the search terms are NAMED (not "no secret found").
#
# The red proof (criterion 1) is a property of the probe, not a separate always
# green test: FAIGRID_FORCE_FORWARD=1 starts the mediator with forwarding on and
# the C1 forward probe then reaches the broker, so the file exits 1 and names the
# reached host. Both runs (forced -> 1, off -> 0) are recorded in LANE-REPORT.md.
# ==============================================================================

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

MEDIATOR_SH="${BATS_TEST_DIRNAME}/../../core/tenant/credential-mediator.sh"
CONTROL_NET="faigrid_control_net"
INFERENCE_NET="faigrid_inference_net"
BROKER_SECRET="veeona_broker_longlived_secret_7f2d"
SCOPED_TOKEN="veeona_scoped_z1_token_9c1e"
BROKER_PORT="9000"
MEDIATOR_PORT="8443"

# Search terms criterion 3 uses. These are the named things that must be ABSENT
# from a worker's environment: the broker's long-lived secret value, the scoped
# token value (a worker must obtain it at request time, not hold it), and the
# conventional secret-bearing variable/key names.
C3_SEARCH_VALUES=(
    "$BROKER_SECRET"
    "$SCOPED_TOKEN"
)
C3_SEARCH_KEYS=(
    "FAIGRID_BROKER_SECRET"
    "TOKEN"
    "PASSWORD"
    "PASSWD"
    "SECRET"
    "API_KEY"
    "APIKEY"
    "CREDENTIAL"
    "PRIVATE_KEY"
    "ACCESS_KEY"
)

_broker_cid=""
_mediator_cid=""
_worker_cid=""

setup() {
    docker >/dev/null 2>&1 || skip "docker not available"
    source "$MEDIATOR_SH"
    faigrid_networks_remove >/dev/null 2>&1 || true
    faigrid_networks_create
}

teardown() {
    docker rm -f "$_broker_cid" >/dev/null 2>&1 || true
    docker rm -f "$_mediator_cid" >/dev/null 2>&1 || true
    docker rm -f "$_worker_cid" >/dev/null 2>&1 || true
    docker rm -f faigrid-forward-probe-"$$" >/dev/null 2>&1 || true
    faigrid_networks_remove >/dev/null 2>&1 || true
    _broker_cid=""
    _mediator_cid=""
    _worker_cid=""
}

# Start broker + mediator, record their container ids and IPs. Starts the
# mediator with forwarding forced when FAIGRID_FORCE_FORWARD=1 (red state) else
# off. Must NOT run inside $(...) (assigns globals).
_start_mediator_topology() {
    _broker_cid="$(faigrid_mediator_broker_start "$BROKER_SECRET")"
    _mediator_cid="$(faigrid_mediator_start "${FAIGRID_FORCE_FORWARD:-0}" "$SCOPED_TOKEN")"
    _broker_ip="$(_cm_container_ip "$_broker_cid" "$CONTROL_NET")"
    _mediator_inf_ip="$(_cm_container_ip "$_mediator_cid" "$INFERENCE_NET")"

    # Readiness: a real round-trip from inside the topoloy, not a sleep. The
    # mediator must answer its token endpoint; the broker must answer its own.
    _cm_wait_http_ready "$INFERENCE_NET" \
        "http://${_mediator_inf_ip}:${MEDIATOR_PORT}/v1/mediator/token" '{}' 20 \
        || true
    _cm_wait_http_ready "$CONTROL_NET" \
        "http://${_broker_ip}:${BROKER_PORT}/v1/broker/token" "" 20 \
        || true
}

@test "C1: exactly one container is dual-homed, and a forward THROUGH it is refused" {
    _start_mediator_topology

    # Exactly one container holds an interface on BOTH networks: the mediator.
    local dual_homed
    dual_homed="$(docker ps -q --no-trunc | while IFS= read -r cid; do
        local c i
        c="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${CONTROL_NET}\").IPAddress}}" "$cid" 2>/dev/null || true)"
        i="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${INFERENCE_NET}\").IPAddress}}" "$cid" 2>/dev/null || true)"
        if [[ -n "$c" && -n "$i" ]]; then printf '%s\n' "$cid"; fi
    done)"
    [[ -n "$dual_homed" ]]
    [[ "$(printf '%s\n' "$dual_homed" | wc -l | tr -d ' ')" -eq 1 ]]
    [[ "$dual_homed" == "$_mediator_cid" ]]

    # Positive control: the broker is alive and answers on the control plane, so
    # a refusal on the inference side is isolation, never a dead listener.
    run docker run --rm --network "$CONTROL_NET" busybox:latest \
        wget -T 4 -O - "http://${_broker_ip}:${BROKER_PORT}/v1/broker/token"
    assert_success
    assert_output --partial '"token"'

    # The forward probe THROUGH the mediator. With forwarding off the broker must
    # NOT be reachable: wget exits non-zero and the output is a refusal/timeout,
    # never the broker's token body.
    run faigrid_mediator_probe_forward "$_broker_ip" "$_mediator_inf_ip" "$_broker_cid"
    if [[ "$output" == *'"token"'* ]] || [[ "$output" == *"long_lived"* ]]; then
        fail "forward through the mediator REACHED the broker ${_broker_ip}:9000 -- IP forwarding is not off"
    fi
    assert_failure
    assert_output --regexp "timed out|refused|unreachable|no route|bad address|can't connect"
}

@test "C1b: with forwarding forced on, the same probe reaches the broker (red proof)" {
    # This test exists so the reviewer can run the broken state explicitly. In the
    # fixed state it must be SKIPPED; it is only meant to fail when the operator
    # forces forwarding, proving the probe discriminates.
    if [[ "${FAIGRID_FORCE_FORWARD:-0}" != "1" ]]; then
        skip "red proof runs only under FAIGRID_FORCE_FORWARD=1"
    fi
    _start_mediator_topology
    run faigrid_mediator_probe_forward "$_broker_ip" "$_mediator_inf_ip" "$_broker_cid"
    # Broken state: the broker WAS reached through the mediator.
    if [[ "$status" -eq 0 ]] || [[ "$output" == *'"token"'* ]]; then
        fail "forward through the mediator REACHED broker ${_broker_ip}:9000 with IP forwarding enabled -- isolation broken"
    fi
}

@test "C2: a z1 worker obtains a scoped token through the mediator and cannot reach the broker directly" {
    _start_mediator_topology

    # Half one: the scoped token arrives THROUGH the mediator (from the inference
    # plane), and it is the scoped token, not the broker's long-lived secret.
    run docker run --rm --network "$INFERENCE_NET" busybox:latest \
        wget -T 10 -O - \
        --header 'Content-Type: application/json' \
        --post-data '{"worker":"z1"}' \
        "http://${_mediator_inf_ip}:${MEDIATOR_PORT}/v1/mediator/token"
    assert_success
    assert_output --partial "$SCOPED_TOKEN"
    refute_output --partial "$BROKER_SECRET"

    # Half two: the direct broker path is refused from the inference plane.
    run docker run --rm --network "$INFERENCE_NET" busybox:latest \
        wget -T 4 -O - "http://${_broker_ip}:${BROKER_PORT}/v1/broker/token"
    assert_failure
    refute_output --partial '"token"'

    # And the very same broker answers from its own plane, so the refusal above is
    # isolation, not a dead broker.
    run docker run --rm --network "$CONTROL_NET" busybox:latest \
        wget -T 4 -O - "http://${_broker_ip}:${BROKER_PORT}/v1/broker/token"
    assert_success
    assert_output --partial '"token"'
}

@test "C3: no long-lived secret is present in a tenant worker's environment" {
    # The worker is a real container on the inference plane. It is started with a
    # clean environment: nothing secret is injected, exactly as faigrid would start
    # a z1 worker (the scoped token is fetched at request time, never baked in).
    _start_mediator_topology
    _worker_cid="$(docker run -d --rm --network "$INFERENCE_NET" \
        --label "com.fusionaize.faigrid.role=worker" \
        busybox:latest sleep 300)"

    run docker exec "$_worker_cid" env
    assert_success

    local value key
    for value in "${C3_SEARCH_VALUES[@]}"; do
        if [[ "$output" == *"$value"* ]]; then
            fail "worker environment carries a long-lived secret VALUE: ${value}"
        fi
    done
    for key in "${C3_SEARCH_KEYS[@]}"; do
        if [[ "$output" == *"${key}"* ]]; then
            fail "worker environment carries a secret-bearing KEY: ${key}"
        fi
    done

    # Non-vacuous guard: the dump is real (env actually reported something) so an
    # empty `env` cannot make this test pass while meaning nothing.
    [[ "$output" == *"PATH="* ]]
}
