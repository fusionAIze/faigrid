#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Core Heart Uninstaller
# ==============================================================================
set -euo pipefail

STACK_DIR="/opt/fusionaize-nexus/core-heart"
COMPOSE_DIR="${STACK_DIR}/compose"
ENV_FILE="${STACK_DIR}/.env"

echo "[nexus-core-heart] Uninstalling core stack..."

if [[ -d "${COMPOSE_DIR}" ]]; then
    cd "${COMPOSE_DIR}" || exit 1
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        echo "[nexus-core-heart] Stopping and removing containers/volumes..."
        docker compose --env-file "${ENV_FILE}" down -v || true
    fi
fi

echo "[nexus-core-heart] Removing stack directory: ${STACK_DIR}"
sudo rm -rf "${STACK_DIR}"

echo "[nexus-core-heart] Uninstallation complete."
