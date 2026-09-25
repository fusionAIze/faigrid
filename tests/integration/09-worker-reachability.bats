#!/usr/bin/env bats
# ==============================================================================
# fusionAIze Grid - the grid-worker serves, and keeps serving (GO-008)
# ==============================================================================
# The grid-worker inference endpoint is http://192.168.178.30:8080/v1 (D7 binds
# the LAN directly; no tunnel, no sidecar). This file proves, from the
# workstation as "another host", that:
#
#   C1  the endpoint answers a model-list request AND the process serving it is
#       not bound to an SSH session - the failure this lane exists to remove was
#       llama-server running as the foreground child of an sshd-session,
#   C2  caffeinate holds the machine awake for as long as the server runs and the
#       server is supervised by a KeepAlive launchd job rather than a live
#       session, so it survives a sleep/wake cycle,
#   C3  when the endpoint is unreachable a consumer is told WHICH endpoint is
#       down, by URL, rather than receiving a generic connection error.
#
# The durable mechanism
# ----------------------
# docs/runbooks/17-worker-service.md installs a user LaunchAgent
# (com.fusionaize.grid-worker) that runs /Users/azrielenoch/start_api.sh at load
# and restarts it on exit. The start script wraps llama-server in caffeinate and
# fails closed without the api-key. The operator installs it; this lane does not
# change the worker.
#
# Transport
# ---------
# The reachability and naming checks (C1's probe, C3) are plain HTTP from this
# host and need no worker login. The supervision checks (C1's ancestry, C2) use
# `ssh azrielenoch@<host>` read-only (`ps`, `pmset`, `launchctl print`). When
# that SSH login is not available - e.g. the workstation key agent lost its
# identity - C1 and C2 fall back to the observable broken pattern: an SSH
# session on this host holding the endpoint open via the start script. That
# fallback is what makes the red state reproducible without worker access.
#
# The api-key
# -----------
# The endpoint requires `Authorization: Bearer <key>` (D7, as amended; measured
# 2026-09-25: no key -> 401). The key is taken from WORKER_API_KEY, else
# LLAMA_API_KEY, else `envctl get faigrid LLAMA_API_KEY`, and is never printed.
#
# RED PROOF
# ---------
# Against the base - the session-bound worker, before the LaunchAgent exists -
# C1 and C2 fail with a real assertion message. They do not skip, because the
# endpoint is reachable; the failure is the assertion that a live SSH session is
# holding the service. Once runbook 17 is applied, no holder remains and the
# launchd ancestry check passes.
# ==============================================================================

fail() { printf 'ASSERTION FAILED: %s\n' "$*" >&2; return 1; }

WORKER_HOST="${WORKER_HOST:-192.168.178.30}"
WORKER_SSH_USER="${WORKER_SSH_USER:-azrielenoch}"
WORKER_PORT="${WORKER_PORT:-8080}"
WORKER_LAUNCHD_LABEL="${WORKER_LAUNCHD_LABEL:-com.fusionaize.grid-worker}"
MODELS_URL="http://${WORKER_HOST}:${WORKER_PORT}/v1/models"

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
WORKER_ENV_LIB="${REPO_ROOT}/worker/lib/worker-env.sh"

# Read the api-key without printing it. Empty output means "no key available".
_worker_api_key() {
    if [ -n "${WORKER_API_KEY:-}" ]; then printf '%s' "$WORKER_API_KEY"; return 0; fi
    if [ -n "${LLAMA_API_KEY:-}" ]; then printf '%s' "$LLAMA_API_KEY"; return 0; fi
    if command -v envctl >/dev/null 2>&1; then
        envctl get faigrid LLAMA_API_KEY 2>/dev/null && return 0
    fi
    return 1
}

# HTTP status of /v1/models as seen from this host. Sends the key when one is
# available; never echoes it.
_curl_models_status() {
    local key
    key="$(_worker_api_key || true)"
    if [ -n "$key" ]; then
        curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
            -H "Authorization: Bearer ${key}" "$MODELS_URL"
    else
        curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$MODELS_URL"
    fi
}

_worker_reachable() {
    nc -z -G 3 "$WORKER_HOST" "$WORKER_PORT" >/dev/null 2>&1
}

_worker_ssh() {
    ssh -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR \
        -o StrictHostKeyChecking=accept-new \
        "${WORKER_SSH_USER}@${WORKER_HOST}" "$@"
}

_ssh_available() {
    _worker_ssh 'true' >/dev/null 2>&1
}

# The broken pattern detectable without a worker login: an SSH session on this
# host whose remote command is the start script is what keeps the endpoint up.
_ssh_holder_on_this_host() {
    ps -Ao pid=,command= 2>/dev/null \
        | awk '$2 == "ssh"' \
        | grep -F "$WORKER_HOST" \
        | grep -F 'start_api.sh' || true
}

# Walk the ancestry of every llama-server process on the worker to pid 1 and
# report whether any ancestor is an SSH session. Emits NO_SSH_ANCESTOR or
# SSH_ANCESTOR ... and exits 3 on the session-bound case.
REMOTE_ANCESTRY_SCRIPT='
pids="$(pgrep -f llama-server 2>/dev/null | tr "\n" " ")"
[ -n "$pids" ] || { echo "NO_LLAMA_PROCESS"; exit 4; }
for pid in $pids; do
    cur="$pid"
    while [ "$cur" -gt 1 ]; do
        set -- $(ps -o ppid=,comm= -p "$cur" 2>/dev/null)
        ppid="${1:-}"
        comm="${2:-}"
        [ -n "$ppid" ] || break
        case "$comm" in
            *sshd*) echo "SSH_ANCESTOR pid=${cur} comm=${comm}"; exit 3 ;;
        esac
        cur="$ppid"
    done
done
echo "NO_SSH_ANCESTOR"
'

setup() {
    command -v curl >/dev/null 2>&1 || skip "curl not available"
    command -v nc >/dev/null 2>&1 || skip "nc not available"
}

@test "C1: the endpoint answers from this host and is not bound to an SSH session" {
    _worker_reachable || skip "worker ${WORKER_HOST}:${WORKER_PORT} not reachable"

    run _curl_models_status
    [ "$status" -eq 0 ] || fail "curl could not probe ${MODELS_URL}: ${output}"
    [ "$output" = "200" ] \
        || fail "expected HTTP 200 from ${MODELS_URL}, got '${output}' (401 means no api-key was supplied)"

    if _ssh_available; then
        run _worker_ssh "$REMOTE_ANCESTRY_SCRIPT"
        if [ "$status" -eq 3 ]; then
            fail "the serving process is bound to an SSH session: ${output}"
        fi
        [ "$status" -eq 0 ] \
            || fail "could not inspect the worker over ssh (exit ${status}): ${output}"
        [[ "$output" == *"NO_SSH_ANCESTOR"* ]] \
            || fail "unexpected ancestry probe output: ${output}"
        echo "# ${MODELS_URL} -> 200; serving process ancestry is free of sshd" >&3
    else
        local holders
        holders="$(_ssh_holder_on_this_host)"
        [ -z "$holders" ] \
            || fail "the endpoint is held open by an SSH session on this host (disable WORKER_SSH inspection only when the worker is supervisor-owned): ${holders}"
        echo "# ${MODELS_URL} -> 200; no SSH session on this host holds the endpoint" >&3
    fi
}

@test "C2: caffeinate holds the machine awake and a KeepAlive launchd job supervises the server" {
    _worker_reachable || skip "worker ${WORKER_HOST}:${WORKER_PORT} not reachable"

    if _ssh_available; then
        run _worker_ssh "pmset -g | grep -i 'sleep prevented by caffeinate'"
        [ "$status" -eq 0 ] \
            || fail "caffeinate is not holding ${WORKER_HOST} awake (the endpoint would drop on sleep): ${output}"

        run _worker_ssh "launchctl print gui/\$(id -u)/${WORKER_LAUNCHD_LABEL} 2>/dev/null | grep -i keepalive"
        [ "$status" -eq 0 ] \
            || fail "no KeepAlive launchd job '${WORKER_LAUNCHD_LABEL}' on ${WORKER_HOST}; the server is supervised by a live session and cannot survive sleep/wake: ${output}"
        echo "# caffeinate active; launchd job ${WORKER_LAUNCHD_LABEL} has KeepAlive" >&3
    else
        local holders
        holders="$(_ssh_holder_on_this_host)"
        [ -z "$holders" ] \
            || fail "the endpoint is held open by an SSH session on this host, so it cannot survive a sleep/wake cycle: ${holders}"
        echo "# no SSH holder on this host; durability must be confirmed by the operator via launchctl" >&3
    fi
}

@test "C3: an unreachable worker is named by endpoint, not a generic failure" {
    # Port 9 is closed on the worker; the point is that the failure names the URL.
    run bash -c 'source "$1"; WORKER_HEALTH_URL="$2" WORKER_HEALTH_TIMEOUT=2 worker_health_check' \
        _ "$WORKER_ENV_LIB" "http://${WORKER_HOST}:9/v1/models"
    [ "$status" -ne 0 ] \
        || fail "health check reported the dead endpoint at ${WORKER_HOST}:9 as healthy"
    [[ "$output" == *"${WORKER_HOST}:9"* ]] \
        || fail "health check did not name the unreachable endpoint URL: ${output}"

    echo "# unreachable endpoint named: ${output}" >&3
}
