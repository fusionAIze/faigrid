#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-status}"
COMPONENT="${2:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

manage_component() {
    local name=$1
    local dir="${STACK_DIR}/compose/${name}"
    if [[ -d "${dir}" ]]; then
        echo "[nexus-external] ${ACTION} on ${name}..."
        docker compose -f "${dir}/docker-compose.yml" "${ACTION}"
    fi
}

case "${ACTION}" in
    start|stop|restart|status|up|down)
        if [[ "${COMPONENT}" == "all" ]]; then
            manage_component "n8n"
            manage_component "plane"
        else
            manage_component "${COMPONENT}"
        fi
        ;;
    install|update|verify|uninstall)
        bash "${SCRIPT_DIR}/${ACTION}.sh" "${COMPONENT}"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|install|update|verify|uninstall} [component]"
        exit 1
        ;;
esac
