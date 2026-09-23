#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Tenant Networks
# ==============================================================================
# Provisions the two tenant isolation networks that the whole nested-tenant
# model rests on:
#
#   faigrid_control_net     trusted control-plane (broker, mediator, preflight)
#   faigrid_inference_net   untrusted inference/worker-plane (z1 workers)
#
# SEC-001: the two networks must NEVER be bridged. This script only creates
# two independent `bridge` networks; it deliberately connects nothing from one
# to the other. The isolation property is proven elsewhere by a refused
# connection (tests/integration/03-tenant-network-isolation.bats), not by this
# script reading back its own config.
#
# Every network carries the creator label
#   com.fusionaize.faigrid.creator=faigrid
# so `docker network inspect` names the faigrid code path as the creator and a
# hand-created network (which lacks the label) is distinguishable.
#
# Bash 3.2 compatible (macOS + Linux). Sourced from tests and from faigrid's
# install path; it performs work only when a subcommand is invoked.
# ==============================================================================

set -euo pipefail

# Resolve the shared library for colors/logging without hard-coding an
# absolute path. The library is optional: if it is absent the logging helpers
# degrade to plain echo.
_LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../workbench/scripts/_lib.sh"
if [[ -f "$_LIB_PATH" ]]; then
    # shellcheck disable=SC1090
    source "$_LIB_PATH"
fi

# ── Network contract ──────────────────────────────────────────────────────────
FAIGRID_CONTROL_NET="faigrid_control_net"
FAIGRID_INFERENCE_NET="faigrid_inference_net"
FAIGRID_NET_CREATOR_LABEL="com.fusionaize.faigrid.creator"
FAIGRID_NET_CREATOR_VALUE="faigrid"

# Emit a log line without depending on _lib.sh being present.
_net_log() {
    if declare -f info >/dev/null 2>&1; then
        info "$*"
    else
        printf '%s\n' "$*"
    fi
}

# True if a Docker network with the given name exists.
faigrid_net_exists() {
    local name="$1"
    docker network inspect "$name" >/dev/null 2>&1
}

# Create one tenant network with the creator label. Returns 0 on create or
# already-present; returns 1 if docker fails.
faigrid_net_create() {
    local name="$1"
    if faigrid_net_exists "$name"; then
        _net_log "tenant network '${name}' already exists; leaving it in place"
        return 0
    fi
    if command -v docker >/dev/null 2>&1; then
        docker network create \
            --driver bridge \
            --label "${FAIGRID_NET_CREATOR_LABEL}=${FAIGRID_NET_CREATOR_VALUE}" \
            "$name" >/dev/null
        _net_log "created tenant network '${name}'"
        return 0
    fi
    printf 'ERROR: docker not found; cannot create tenant network %s\n' "$name" >&2
    return 1
}

# Provision both tenant networks. Never errors if they exist; creates them
# otherwise. This is the faigrid code path VT-003 and VT-005 build on.
faigrid_networks_create() {
    faigrid_net_create "$FAIGRID_CONTROL_NET"
    faigrid_net_create "$FAIGRID_INFERENCE_NET"
}

# Remove a tenant network only if faigrid created it (creator label set).
# A foreign network is never touched.
faigrid_net_remove() {
    local name="$1"
    if ! faigrid_net_exists "$name"; then
        return 0
    fi
    local creator
    creator="$(docker network inspect -f "{{index .Labels \"${FAIGRID_NET_CREATOR_LABEL}\"}}" "$name" 2>/dev/null || true)"
    if [[ "$creator" != "${FAIGRID_NET_CREATOR_VALUE}" ]]; then
        _net_log "tenant network '${name}' not created by faigrid; refusing to remove"
        return 0
    fi
    docker network rm "$name" >/dev/null
    _net_log "removed tenant network '${name}'"
}

# Tear down both networks, but only the ones faigrid owns.
faigrid_networks_remove() {
    faigrid_net_remove "$FAIGRID_INFERENCE_NET"
    faigrid_net_remove "$FAIGRID_CONTROL_NET"
}

# CLI entry point: `create`, `remove`, or `status`.
faigrid_networks_main() {
    case "${1:-}" in
        create)
            faigrid_networks_create
            ;;
        remove)
            faigrid_networks_remove
            ;;
        status)
            if faigrid_net_exists "$FAIGRID_CONTROL_NET" && faigrid_net_exists "$FAIGRID_INFERENCE_NET"; then
                printf 'tenant networks present: %s, %s\n' "$FAIGRID_CONTROL_NET" "$FAIGRID_INFERENCE_NET"
            else
                printf 'tenant networks incomplete\n' >&2
                return 1
            fi
            ;;
        *)
            printf 'usage: %s {create|remove|status}\n' "${BASH_SOURCE[0]}" >&2
            return 2
            ;;
    esac
}

# Only act as a CLI when executed directly, never when sourced by a test.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    faigrid_networks_main "$@"
fi
