#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Core Heart Pre-Backup Hook
# ==============================================================================
set -euo pipefail

# This script is triggered by the central backup orchestrator.
# It dumps databases and prepares volume snapshots before the main restic run.

DUMP_DIR="/var/backups/grid-core"
sudo mkdir -p "${DUMP_DIR}"
sudo chmod 700 "${DUMP_DIR}"

TS="$(date +%F_%H%M%S)"

echo "[core-heart] [DUMP] PostgreSQL..."
if docker ps --format '{{.Names}}' | grep -q "nexus-postgres"; then
    # shellcheck disable=SC1091
    [[ -f .env ]] && source .env
    docker exec nexus-postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "${DUMP_DIR}/postgres_${TS}.sql"
fi

echo "[core-heart] [DUMP] n8n volume states..."
if docker volume ls -q | grep -q "nexus_n8n_data"; then
    docker run --rm \
      -v nexus_n8n_data:/data \
      -v "${DUMP_DIR}:/backup" \
      alpine:3.20 sh -lc "cd /data && tar -czf /backup/n8n_data_${TS}.tar.gz ."
fi

# Cleanup old dumps (keep last 3 local dumps for quick access)
find "${DUMP_DIR}" -type f -mtime +3 -delete

echo "[core-heart] Pre-backup sequence complete."
