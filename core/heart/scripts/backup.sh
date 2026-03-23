#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Sovereign Backup Script
# ==============================================================================
set -euo pipefail

# Define operational boundaries
BACKUP_DIR="/var/backups/faigrid"
RETENTION_DAYS=7
TS="$(date +%F_%H%M%S)"

# Ensure strict permissions
sudo mkdir -p "${BACKUP_DIR}"
sudo chmod 700 "${BACKUP_DIR}"

echo "============================================================"
echo " Starting explicit fusionAIze Grid Backup [${TS}]"
echo "============================================================"

# 1. Backup Core State and Topology (Crucial for Solo/SMB Operator Recovery)
echo "[1/4] Snapshotting Grid Topology and State..."
if [[ -f "${HOME}/.grid-state" ]]; then
    sudo cp "${HOME}/.grid-state" "${BACKUP_DIR}/grid-state_${TS}.backup"
fi
if [[ -d "${HOME}/.config/faigrid" ]]; then
    sudo tar -czf "${BACKUP_DIR}/grid_secrets_${TS}.tar.gz" -C "${HOME}/.config/faigrid" .
fi
sudo chmod 600 "${BACKUP_DIR}"/grid*

# 2. Backup PostgreSQL Core Database
echo "[2/4] Dumping PostgreSQL Orchestration Database..."
if docker ps --format '{{.Names}}' | grep -q "grid-postgres"; then
    docker exec grid-postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "${BACKUP_DIR}/postgres_${TS}.sql"
    sudo chmod 600 "${BACKUP_DIR}/postgres_${TS}.sql"
else
    echo "  -> Skip: Postgres container not running."
fi

# 3. Backup workflow volumes (n8n, etc.)
echo "[3/4] Archiving internal queue/workflow volumes..."
if docker volume ls -q | grep -q "grid_core_n8n_data"; then
    docker run --rm \
      -v grid_core_n8n_data:/data \
      -v "${BACKUP_DIR}:/backup" \
      alpine:3.20 sh -lc "cd /data && tar -czf /backup/n8n_data_${TS}.tar.gz ."
      sudo chmod 600 "${BACKUP_DIR}/n8n_data_${TS}.tar.gz"
else
    echo "  -> Skip: Volume grid_core_n8n_data not found."
fi

# 4. Enforce Retention Discipline
echo "[4/4] Enforcing retention discipline (${RETENTION_DAYS} days)..."
sudo find "${BACKUP_DIR}" -type f -mtime +${RETENTION_DAYS} -delete

echo "============================================================"
echo " Backup cycle complete -> ${BACKUP_DIR}"
echo "============================================================"
sudo ls -lah "${BACKUP_DIR}" | grep "${TS}"
