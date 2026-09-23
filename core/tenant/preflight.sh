#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Tenant substrate preflight (VT-003)
# ==============================================================================
# Handover clause 5: both external tenant networks must be provisioned and
# healthy BEFORE any tenant workload spawns.
#
# This file owns two things and nothing else:
#
#   tenant_preflight()   the GATE. Decides readiness and prints, per network,
#                        precisely why it is not ready. It creates nothing.
#   tenant_start()       the GUARDED ENTRY. Runs the gate first; on a refusal it
#                        returns before any `docker run`, so a container is only
#                        ever created on a substrate the gate accepted.
#
# The DEFINITION of "healthy" lives here, in faigrid_net_readiness_reason(), and
# not in any test assertion. A tenant network is ready iff ALL of:
#
#   1. it exists;
#   2. its driver is `bridge` - a non-bridge network cannot carry tenant traffic;
#   3. it carries the faigrid creator label that VT-002 stamps on its networks,
#      so a hand-created look-alike is not mistaken for the substrate;
#   4. it has at least one usable IPAM subnet - a network with no address pool
#      cannot address a tenant container.
#
# The gate inspects the network with `docker network inspect` ONLY. It does NOT
# launch a probe container to test reachability: any probe would land in
# `docker ps -a` and so break criterion 3 ("the refusal precedes any tenant
# container creation"). The evidence that nothing spawned is the `docker ps -a`
# snapshot diff in tests/unit/06-tenant-preflight.bats, never this file reading
# itself back.
#
# Reuses VT-002's network contract (core/tenant/networks.sh) read-only. It
# sources that file, which is why it must never be run from a directory other
# than its own. Bash 3.2 compatible (macOS + Linux).
# ==============================================================================

_PF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
. "${_PF_DIR}/networks.sh"

# Every container the guarded entry below starts is named under this prefix, so
# the `docker ps -a` evidence for criterion 3 can be scoped to the tenant
# container namespace this path is the only producer of. A global daemon-wide
# snapshot is unsafe on a shared engine: a concurrent lane (VT-005, same
# substrate) starts unrelated containers and would be misread as a tenant having
# spawned despite the refusal.
FAIGRID_TENANT_CONTAINER_PREFIX="faigrid-tenant-"

# Log through _lib.sh when present, degrade to plain output otherwise.
_pf_ok() {
    if declare -f info >/dev/null 2>&1; then info "$*"; else printf '%s\n' "$*"; fi
}
_pf_error() {
    if declare -f error >/dev/null 2>&1; then error "$*"; else printf '%s\n' "$*" >&2; fi
}

# ------------------------------------------------------------------------------
# The health definition. Prints an EMPTY string when NAME is a ready tenant
# network; otherwise prints the single reason it is not ready. Every caller that
# needs to know what "healthy" means asks this function - including the tests,
# which is why the definition is not duplicated into an assertion.
# ------------------------------------------------------------------------------
faigrid_net_readiness_reason() {
    local name="$1"

    if ! faigrid_net_exists "$name"; then
        printf '%s' "missing (network does not exist)"
        return 0
    fi

    local driver
    driver="$(docker network inspect -f '{{.Driver}}' "$name" 2>/dev/null || true)"
    if [[ "$driver" != "bridge" ]]; then
        printf '%s' "unhealthy (driver is '${driver}', expected 'bridge')"
        return 0
    fi

    local creator
    creator="$(docker network inspect \
        -f "{{index .Labels \"${FAIGRID_NET_CREATOR_LABEL}\"}}" "$name" 2>/dev/null || true)"
    if [[ "$creator" != "${FAIGRID_NET_CREATOR_VALUE}" ]]; then
        printf '%s' "unhealthy (not created by faigrid: creator label '${FAIGRID_NET_CREATOR_LABEL}' is '${creator:-unset}')"
        return 0
    fi

    local subnets
    subnets="$(docker network inspect \
        -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$name" 2>/dev/null || true)"
    if [[ -z "${subnets//[[:space:]]/}" ]]; then
        printf '%s' "unhealthy (no IPAM subnet: cannot address a tenant container)"
        return 0
    fi

    printf '%s' ""
}

# ------------------------------------------------------------------------------
# The gate. Returns 0 only when EVERY tenant network is ready. Otherwise it
# names each network that is not ready (with the reason above) on stderr and
# returns 1. It creates nothing, on any path.
# ------------------------------------------------------------------------------
tenant_preflight() {
    local net reason failed=0

    for net in "$FAIGRID_CONTROL_NET" "$FAIGRID_INFERENCE_NET"; do
        reason="$(faigrid_net_readiness_reason "$net")"
        if [[ -n "$reason" ]]; then
            _pf_error "tenant preflight REFUSED: network '${net}' is not ready - ${reason}"
            failed=1
        fi
    done

    if [[ "$failed" -ne 0 ]]; then
        return 1
    fi

    _pf_ok "tenant preflight OK: '${FAIGRID_CONTROL_NET}' and '${FAIGRID_INFERENCE_NET}' are ready"
    return 0
}

# ------------------------------------------------------------------------------
# Guarded tenant start.
#   $1  container name, optional (default faigrid-tenant-$$)
#   $2  image, optional (default busybox:latest)
#   $3  network, optional (default the control network)
# The gate runs FIRST. On refusal this returns 1 and creates NOTHING; only an
# accepted substrate reaches `docker run`. Callers name tenant containers under
# FAIGRID_TENANT_CONTAINER_PREFIX; the default does, so a caller that omits the
# name still lands in the namespace criterion 3 observes.
# ------------------------------------------------------------------------------
tenant_start() {
    local name="${1:-${FAIGRID_TENANT_CONTAINER_PREFIX}$$}"
    local image="${2:-busybox:latest}"
    local network="${3:-$FAIGRID_CONTROL_NET}"

    if ! tenant_preflight; then
        _pf_error "tenant start '${name}' aborted: substrate is not ready; no container was created"
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        _pf_error "tenant start '${name}' failed: docker not found"
        return 1
    fi

    docker run -d --name "$name" --network "$network" "$image" sleep 3600 >/dev/null
}

# CLI: `preflight.sh [check]` exits 0 when the substrate is ready and non-zero
# with the named reason otherwise.
tenant_preflight_main() {
    case "${1:-check}" in
        check)
            tenant_preflight
            ;;
        *)
            printf 'usage: %s [check]\n' "${BASH_SOURCE[0]}" >&2
            return 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    tenant_preflight_main "$@"
fi
