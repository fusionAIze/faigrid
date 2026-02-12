#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/var/backups/nexus-core-heart"
TS="$(date +%F_%H%M%S)"
mkdir -p "${BACKUP_DIR}"

echo "[backup] postgres dump..."
docker exec -t nexus-postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "${BACKUP_DIR}/postgres_${TS}.sql"

echo "[backup] n8n volume archive..."
docker run --rm \
  -v nexus_n8n_data:/data \
  -v "${BACKUP_DIR}:/backup" \
  alpine:3.20 sh -lc "cd /data && tar -czf /backup/n8n_data_${TS}.tar.gz ."

echo "[backup] done -> ${BACKUP_DIR}"
ls -lah "${BACKUP_DIR}" | tail -n 10
