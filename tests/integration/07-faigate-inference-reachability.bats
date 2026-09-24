#!/usr/bin/env bats
# ==============================================================================
# fusionAIze Grid - faigate reachability on the inference plane (GO-002)
# ==============================================================================
# veeona's z1 and z2 zones address the gate as http://faigate:8090/v1. This file
# proves, on the live nexus-core substrate, that:
#
#   C1  a container on faigrid_inference_net reaches the gate and gets an
#       OpenAI-compatible model list (HTTP 200 with a non-empty `data` array),
#   C2  the same gate is NOT reachable from faigrid_control_net, proven by a
#       connection-level refusal -- not by reading the compose file, and with a
#       positive control so a dead gate can never read as a successful refusal,
#   C3  the five incumbent containers are not mutated by this lane: their
#       identity, start time, restart count and network attachment are stable
#       across the run.
#
# How the probe tells REACHED from NOT REACHED
# --------------------------------------------
# REACHED is unambiguous: curl exits 0 and the body carries `"object":"list"`
# with model entries. NOT REACHED is a connection-level failure: a name that
# does not resolve inside the control network, or an IP that does not answer.
# An HTTP status from the gate (404 included) would mean it ANSWERED, so 404 is
# explicitly rejected as refusal evidence.
#
# C3 scope
# --------
# The test proves the run does not mutate the incumbents (a snapshot at
# setup_file time is diffed at C3). The deployment's own before/after capture,
# byte-identical over Id, State.StartedAt, RestartCount and network attachment,
# is recorded in docs/runbooks/13-faigate-on-inference-net.md; the test file is
# not the place where a historical deployment action is witnessed.
#
# Transport
# ---------
# The checks run against the docker daemon on nexus-core, addressed with
# `docker -H ssh://<host>`, so no bats installation is needed on the node.
# Off that host -- or when the daemon is unreachable -- the file skips rather
# than failing a CI runner that has no substrate: set NEXUS_HOST to point
# elsewhere. The red state is produced with the gate absent, where C1 and C2
# fail with a real assertion message.
# ==============================================================================

# bats-support carries `fail`, but the test libs under tests/.libs are only
# present after tests/run_tests.sh bootstraps them. This file defines its own
# `fail` so that a plain `bats tests/integration/07-...` invocation fails with a
# real assertion message instead of a 127 command-not-found, which the gate
# would read as a setup error. It is equivalent to bats-support's.
fail() { printf 'ASSERTION FAILED: %s\n' "$*" >&2; return 1; }

NEXUS_HOST="${NEXUS_HOST:-nexus-core}"

CONTROL_NET="faigrid_control_net"
INFERENCE_NET="faigrid_inference_net"
FAIGATE_NAME="faigate"
FAIGATE_PORT="8090"
FAIGATE_MODELS_URL="http://${FAIGATE_NAME}:${FAIGATE_PORT}/v1/models"

INCUMBENTS="grid-minio grid-core-n8n grid-core-n8n-worker grid-postgres grid-redis"
COMPOSE_NET="compose_grid_net"

# Docker CLI pointed at the live daemon. Formatting (inspect -f, run) is applied
# by the local client, so no remote shell quoting is involved.
rdocker() {
    docker -H "ssh://${NEXUS_HOST}" "$@"
}

_remote_available() {
    rdocker version >/dev/null 2>&1
}

# One line per incumbent: name, immutable Id, start time, restart count and the
# set of attached networks. This is the exact state criterion 3 measures.
_incumbents_snapshot() {
    local c
    for c in $INCUMBENTS; do
        rdocker inspect \
            -f '{{.Name}} Id={{.Id}} StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}} Networks={{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' \
            "$c"
    done
}

# HTTP status of the gate as seen from a container on the given network, by DNS
# name. -o /dev/null keeps the body out; only the code is returned.
_probe_status_from_net() {
    local net="$1"
    rdocker run --rm --net "$net" curlimages/curl \
        -s -o /dev/null -w '%{http_code}' --max-time 10 "$FAIGATE_MODELS_URL"
}

# Body of the gate's model list as seen from a container on the given network.
_probe_body_from_net() {
    local net="$1"
    rdocker run --rm --net "$net" curlimages/curl \
        -s --max-time 10 "$FAIGATE_MODELS_URL"
}

setup() {
    command -v docker >/dev/null 2>&1 || skip "docker CLI not available"
    _remote_available || skip "docker daemon on '${NEXUS_HOST}' not reachable (set NEXUS_HOST)"
}

setup_file() {
    # Snapshot before any test runs; C3 diffs against this.
    if command -v docker >/dev/null 2>&1 && _remote_available; then
        _incumbents_snapshot > "${BATS_FILE_TMPDIR}/incumbents.before" 2>/dev/null || true
    fi
}

@test "C1: a container on faigrid_inference_net gets HTTP 200 and a model list from faigate" {
    run _probe_status_from_net "$INFERENCE_NET"
    [ "$status" -eq 0 ] \
        || fail "curl could not run against ${FAIGATE_NAME} on ${INFERENCE_NET} (exit ${status}): ${output}"

    [ "$output" = "200" ] \
        || fail "expected HTTP 200 from ${FAIGATE_MODELS_URL} on ${INFERENCE_NET}, got '${output}'"

    run _probe_body_from_net "$INFERENCE_NET"
    [ "$status" -eq 0 ] || fail "model-list request from ${INFERENCE_NET} failed (exit ${status}): ${output}"

    [[ "$output" == *'"object":"list"'* ]] \
        || fail "response is not an OpenAI-compatible list object: ${output:0:200}"
    [[ "$output" == *'"id"'* ]] \
        || fail "model list carries no model entries: ${output:0:200}"

    local model_count
    model_count="$(printf '%s' "$output" | grep -o '"object":"model"' | wc -l | tr -d ' ')"
    [ "${model_count:-0}" -ge 1 ] \
        || fail "model list carries zero model objects"

    echo "# ${FAIGATE_MODELS_URL} on ${INFERENCE_NET} -> 200, ${model_count} model entries" >&3
}

@test "C2: faigate is refused from faigrid_control_net (connection-level, not a 404)" {
    # Positive control: the very same gate answers on its own network. Without
    # this, a dead gate would make the refusal below vacuously true.
    run _probe_status_from_net "$INFERENCE_NET"
    [ "$output" = "200" ] \
        || fail "positive control failed: ${FAIGATE_NAME} did not answer on ${INFERENCE_NET} (got '${output}')"

    # Refusal 1: by DNS name from the control network.
    run rdocker run --rm --net "$CONTROL_NET" curlimages/curl \
        -sS --max-time 10 "$FAIGATE_MODELS_URL"
    [ "$status" -ne 0 ] \
        || fail "control_net REACHED ${FAIGATE_NAME} -- the SEC-001 boundary is broken"
    [[ "$output" != *"404"* ]] \
        || fail "control_net received HTTP 404 from ${FAIGATE_NAME} -- the gate answered; that is not a refusal"

    local by_name_out="$output" by_name_status="$status"

    # Refusal 2: by the IP the gate holds on the inference network. Even if the
    # name happened to resolve, the address must not answer across networks.
    local ip
    ip="$(rdocker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$FAIGATE_NAME" 2>/dev/null | tr -d ' ')"
    [ -n "$ip" ] || fail "could not resolve ${FAIGATE_NAME}'s inference-network IP to run the IP refusal probe"

    run rdocker run --rm --net "$CONTROL_NET" curlimages/curl \
        -sS --max-time 8 "http://${ip}:${FAIGATE_PORT}/v1/models"
    [ "$status" -ne 0 ] \
        || fail "control_net REACHED ${FAIGATE_NAME} at ${ip} -- network isolation is broken"

    echo "# control-net refusal by name: exit ${by_name_status} -- ${by_name_out}" >&3
    echo "# control-net refusal by IP ${ip}: exit ${status} -- ${output}" >&3
}

@test "C3: the five incumbents are unchanged across the run (Id, StartedAt, RestartCount, networks)" {
    local before="${BATS_FILE_TMPDIR}/incumbents.before"
    [ -s "$before" ] || skip "incumbent baseline not captured (daemon unreachable at setup_file)"

    local after
    after="$(mktemp)"
    _incumbents_snapshot > "$after"

    # Non-vacuous: all five must be present in both captures.
    local n_before n_after
    n_before="$(grep -c '^/grid-' "$before" || true)"
    n_after="$(grep -c '^/grid-' "$after" || true)"
    [ "$n_before" -eq 5 ] || fail "baseline names ${n_before} incumbents, expected 5"
    [ "$n_after" -eq 5 ] || fail "current state names ${n_after} incumbents, expected 5"

    run diff "$before" "$after"
    if [ "$status" -ne 0 ]; then
        fail "an incumbent changed during the run: $(printf '%s' "$output" | tr '\n' '|')"
    fi

    # And each one is attached ONLY to compose_grid_net, with RestartCount=0.
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" == *"RestartCount=0"* ]] \
            || fail "incumbent is not at RestartCount=0: ${line}"
        [[ "$line" == *"Networks=${COMPOSE_NET} "* ]] \
            || fail "incumbent is not attached to ${COMPOSE_NET} only: ${line}"
    done < "$after"
}
