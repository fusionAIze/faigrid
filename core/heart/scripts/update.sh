#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"

# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"
resolve_compose_paths

if [[ ! -d "${COMPOSE_DIR}" ]]; then
    error "Compose directory not found: ${COMPOSE_DIR}"
    exit 1
fi

cd "${COMPOSE_DIR}" || exit 1

echo "[nexus-core-heart] Checking for image updates..."
PULL_OUTPUT=$(docker compose --env-file "${ENV_FILE}" pull 2>&1)
echo "$PULL_OUTPUT"

echo "[nexus-core-heart] Applying stack changes..."
docker compose --env-file "${ENV_FILE}" up -d

if echo "$PULL_OUTPUT" | grep -q "Downloaded newer image"; then
    success "[nexus-core-heart] Successfully updated to newer images."
else
    info "[nexus-core-heart] Services already using latest images. Restarted."
fi

docker image prune -f
