#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Core Heart Uninstaller
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"

# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"
resolve_compose_paths

echo "[nexus-core-heart] Uninstalling core stack..."

if [[ -d "${COMPOSE_DIR}" ]]; then
    cd "${COMPOSE_DIR}" || exit 1
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        echo "[nexus-core-heart] Stopping and removing containers/volumes..."
        docker compose --env-file "${ENV_FILE}" down -v || true
    fi
fi

echo "[nexus-core-heart] Removing stack directory: ${STACK_DIR}"
sudo rm -rf "${STACK_DIR}"

echo "[nexus-core-heart] Uninstallation complete."
