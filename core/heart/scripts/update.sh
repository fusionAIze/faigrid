#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="/opt/fusionaize-nexus/core-heart"
COMPOSE_DIR="${STACK_DIR}/compose"
ENV_FILE="${STACK_DIR}/.env"

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
