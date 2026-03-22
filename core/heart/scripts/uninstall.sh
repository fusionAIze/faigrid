#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Core Heart Uninstaller
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"

# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"
resolve_compose_paths

echo "[grid-core-heart] Uninstalling core stack..."

if [[ -d "${COMPOSE_DIR}" ]]; then
    cd "${COMPOSE_DIR}" || exit 1
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        echo "[grid-core-heart] Stopping and removing containers/volumes..."
        docker compose --env-file "${ENV_FILE}" down -v || true
    fi
fi

echo "[grid-core-heart] Removing stack directory: ${STACK_DIR}"
sudo rm -rf "${STACK_DIR}"

echo "[grid-core-heart] Uninstallation complete."
