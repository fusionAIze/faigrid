#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="/opt/fusionaize-nexus/core-heart"
COMPOSE_DIR="${STACK_DIR}/compose"
ENV_FILE="${STACK_DIR}/.env"

cd "${COMPOSE_DIR}"
docker compose --env-file "${ENV_FILE}" pull
docker compose --env-file "${ENV_FILE}" up -d
docker image prune -f
echo "[nexus-core-heart] updated"
