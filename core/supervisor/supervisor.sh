#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Supervisor (GO-001 / operator decision D5)
# ==============================================================================
# The Supervisor is the umbrella over Scheduler, Runner Pool and Recovery Engine,
# presented through the Control API on faigrid_control_net:5000. It is the
# surface veeona calls as register(), poll(), recovery_history(job_id) and
# max_workers.
#
#   * Operator decision D5: Supervisor becomes the stack's umbrella term for the
#     faigrid service that presents Scheduler, Runner Pool and Recovery Engine
#     through the Control API.
#   * SEC-001: the control API answers ONLY on faigrid_control_net. A probe from
#     faigrid_inference_net must be REFUSED (connection refused / timeout), never
#     a 404.
#   * recovery_history reads the journal core/tenant/recovery-journal.sh writes.
#     It does NOT introduce a second, parallel record; correlation_id is
#     preserved verbatim.
#   * Follows the credential-mediator idiom: inline python3 -c, no bind-mount.
#     The journal directory IS bind-mounted (read-only) so the Python process
#     inside the container can read it.
#
# Sourced from tests and the install path. It only performs work when a function
# is invoked. Bash 3.2 compatible (macOS + Linux).
# ==============================================================================

set -euo pipefail

_SUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=control-api.sh
. "${_SUP_SCRIPT_DIR}/control-api.sh"

# ── Supervisor contract ─────────────────────────────────────────────────────────
FAIGRID_SUPERVISOR_IMAGE="${FAIGRID_SUPERVISOR_IMAGE:-python:3.10-slim}"
FAIGRID_SUPERVISOR_CONTAINER="faigrid-supervisor"
FAIGRID_SUPERVISOR_PORT="5000"
FAIGRID_SUPERVISOR_HOSTNAME="faigrid-core"
FAIGRID_SUPERVISOR_URL="http://${FAIGRID_SUPERVISOR_HOSTNAME}:${FAIGRID_SUPERVISOR_PORT}"
FAIGRID_PROBE_IMAGE="${FAIGRID_PROBE_IMAGE:-busybox:latest}"
# Journal dir and max workers are read dynamically in the start function to
# respect env overrides set after sourcing this file.
_SUP_DEFAULT_JOURNAL_DIR="/var/lib/faigrid/recovery"
_SUP_DEFAULT_MAX_WORKERS="4"

# ── Logging (degrades to printf if _lib.sh is absent) ───────────────────────────
_sup_log() {
    if declare -f info >/dev/null 2>&1; then
        info "$*"
    else
        printf '%s\n' "$*"
    fi
}

# ── Docker helpers ──────────────────────────────────────────────────────────────

# True if docker is usable.
_sup_docker_available() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

# True if the supervisor container is running.
faigrid_supervisor_running() {
    docker inspect "$FAIGRID_SUPERVISOR_CONTAINER" >/dev/null 2>&1
}

# ── Supervisor lifecycle ────────────────────────────────────────────────────────

# Start the Supervisor container on faigrid_control_net. Echoes the container id.
# Bind-mounts the recovery journal directory (read-only) so recovery_history can
# read it from inside the container.
faigrid_supervisor_start() {
    local control_net="${1:-faigrid_control_net}"

    if faigrid_supervisor_running; then
        _sup_log "supervisor already running"
        docker inspect -f '{{.Id}}' "$FAIGRID_SUPERVISOR_CONTAINER"
        return 0
    fi

    local journal_dir="${SUPERVISOR_RECOVERY_JOURNAL_DIR:-$_SUP_DEFAULT_JOURNAL_DIR}"
    local max_workers="${FAIGRID_SUPERVISOR_MAX_WORKERS:-$_SUP_DEFAULT_MAX_WORKERS}"
    if [[ ! -d "$journal_dir" ]]; then
        mkdir -p "$journal_dir"
    fi

    local cid
    cid="$(docker run -d --rm \
        --name "$FAIGRID_SUPERVISOR_CONTAINER" \
        --hostname "$FAIGRID_SUPERVISOR_HOSTNAME" \
        --network "$control_net" \
        --label "com.fusionaize.faigrid.role=supervisor" \
        -e "SUPERVISOR_RECOVERY_JOURNAL_DIR=${journal_dir}" \
        -e "SUPERVISOR_MAX_WORKERS=${max_workers}" \
        -v "${journal_dir}:${journal_dir}:ro" \
        "$FAIGRID_SUPERVISOR_IMAGE" \
        python3 -c "$(_supervisor_server)")"

    _sup_log "supervisor started on ${control_net}:${FAIGRID_SUPERVISOR_PORT} (container ${cid})"
    printf '%s\n' "$cid"
}

# Stop and remove the supervisor container.
faigrid_supervisor_stop() {
    docker rm -f "$FAIGRID_SUPERVISOR_CONTAINER" >/dev/null 2>&1 || true
    _sup_log "supervisor stopped"
}

# Wait until the supervisor answers on the given network. Returns 0 once ready,
# 1 after MAX_TRIES.
faigrid_supervisor_wait_ready() {
    local net="${1:-faigrid_control_net}"
    local tries="${2:-30}"
    local i
    for i in $(seq 1 "$tries"); do
        if docker run --rm --network "$net" "$FAIGRID_PROBE_IMAGE" \
            wget -q -T 2 -O /dev/null \
            "http://${FAIGRID_SUPERVISOR_HOSTNAME}:${FAIGRID_SUPERVISOR_PORT}/v1/supervisor/max_workers" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# ── Probe surface ───────────────────────────────────────────────────────────────

# Probe the supervisor FROM A CONTAINER on the given network. Returns 0 if the
# supervisor answers, 1 if refused/timed out. Echoes HTTP status code on stdout.
# This is the PROOF: it runs from a container, never from the node shell.
faigrid_supervisor_probe() {
    local net="$1"
    local endpoint="${2:-/v1/supervisor/max_workers}"
    local http_code
    http_code="$(docker run --rm --network "$net" "$FAIGRID_PROBE_IMAGE" \
        wget -q -T 3 -O /dev/null -S \
        "http://${FAIGRID_SUPERVISOR_HOSTNAME}:${FAIGRID_SUPERVISOR_PORT}${endpoint}" 2>&1 | grep -E '^  HTTP' | tail -n 1 | awk '{print $2}')" || true
    if [[ -n "$http_code" ]]; then
        printf '%s\n' "$http_code"
        return 0
    fi
    printf '000\n'
    return 1
}

# Probe the supervisor's recovery_history endpoint from a container on the given
# network. Returns the JSON body on stdout.
faigrid_supervisor_recovery_history() {
    local net="$1"
    local job_id="$2"
    docker run --rm --network "$net" "$FAIGRID_PROBE_IMAGE" \
        wget -q -T 5 -O - \
        "http://${FAIGRID_SUPERVISOR_HOSTNAME}:${FAIGRID_SUPERVISOR_PORT}/v1/supervisor/recovery_history/${job_id}" 2>/dev/null || true
}

# Register a worker via the supervisor API from a container on the given network.
faigrid_supervisor_register() {
    local net="$1"
    local worker="$2"
    local payload="{\"worker\":\"${worker}\"}"
    docker run --rm --network "$net" "$FAIGRID_PROBE_IMAGE" \
        wget -q -T 5 -O - \
        --header 'Content-Type: application/json' \
        --post-data "$payload" \
        "http://${FAIGRID_SUPERVISOR_HOSTNAME}:${FAIGRID_SUPERVISOR_PORT}/v1/supervisor/register" 2>/dev/null || true
}

# Poll the supervisor from a container on the given network.
faigrid_supervisor_poll() {
    local net="$1"
    docker run --rm --network "$net" "$FAIGRID_PROBE_IMAGE" \
        wget -q -T 5 -O - \
        "http://${FAIGRID_SUPERVISOR_HOSTNAME}:${FAIGRID_SUPERVISOR_PORT}/v1/supervisor/poll" 2>/dev/null || true
}

# Get max_workers from the supervisor from a container on the given network.
faigrid_supervisor_max_workers() {
    local net="$1"
    docker run --rm --network "$net" "$FAIGRID_PROBE_IMAGE" \
        wget -q -T 5 -O - \
        "http://${FAIGRID_SUPERVISOR_HOSTNAME}:${FAIGRID_SUPERVISOR_PORT}/v1/supervisor/max_workers" 2>/dev/null || true
}
