#!/usr/bin/env bash
set -euo pipefail

COMPONENT="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

uninstall_component() {
    local name=$1
    local dir="${STACK_DIR}/compose/${name}"
    if [[ -d "${dir}" ]]; then
        echo "[nexus-external] Uninstalling ${name}..."
        docker compose -f "${dir}/docker-compose.yml" down -v || true
    fi
}

case "${COMPONENT}" in
    n8n)   uninstall_component "n8n" ;;
    plane) uninstall_component "plane" ;;
    all)   uninstall_component "n8n"; uninstall_component "plane" ;;
    *)     echo "Unknown component: ${COMPONENT}"; exit 1 ;;
esac

echo "[nexus-external] Uninstallation complete."
