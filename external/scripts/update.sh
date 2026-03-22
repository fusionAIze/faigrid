#!/usr/bin/env bash
set -euo pipefail

COMPONENT="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd || exit 1)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd || exit 1)"

update_component() {
    local name=$1
    local dir="${STACK_DIR}/compose/${name}"
    if [[ -d "${dir}" ]]; then
        echo "[grid-external] Updating ${name}..."
        docker compose -f "${dir}/docker-compose.yml" pull
        docker compose -f "${dir}/docker-compose.yml" up -d
    fi
}

case "${COMPONENT}" in
    n8n)   update_component "n8n" ;;
    plane) update_component "plane" ;;
    all)   update_component "n8n"; update_component "plane" ;;
    *)     echo "Unknown component: ${COMPONENT}"; exit 1 ;;
esac

echo "[grid-external] Update complete."
