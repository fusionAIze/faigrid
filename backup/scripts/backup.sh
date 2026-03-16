#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Centralized Backup Orchestrator
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd || exit 1)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd || exit 1)"

# 1. Load Config
CONFIG_FILE="${SCRIPT_DIR}/_backup_config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[nexus-backup] [ERROR] Configuration file missing: ${CONFIG_FILE}"
    echo "Please copy _backup_config.sh.template to _backup_config.sh and configure it."
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# 2. Setup Logging
LOG_DIR="/var/log/nexus"
sudo mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="${LOG_DIR}/backup.log"

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log "INFO" "Starting backup cycle..."

# 3. Trigger Pre-Backup Hooks
log "INFO" "Running pre-backup hooks..."
find "${PROJECT_ROOT}" -name "backup-pre.sh" -type f -print0 | while IFS= read -r -d '' hook; do
    log "INFO" "Executing hook: ${hook}"
    bash "$hook" || log "WARN" "Hook failed: ${hook}"
done

# 4. Perform Restic Backup
log "INFO" "Initiating Restic snapshot..."

# Paths to include
BACKUP_PATHS=(
    "${PROJECT_ROOT}"
    "/etc/nexus"
    "$HOME/.nexus-state"
)

# Filter existing paths
VALID_PATHS=()
for p in "${BACKUP_PATHS[@]}"; do
    if [[ -e "$p" ]]; then
        VALID_PATHS+=("$p")
    fi
done

restic backup "${VALID_PATHS[@]}" \
    --header "X-Nexus-Backup: true" \
    --tag "nexus-labs" \
    --host "$(hostname)" \
    --exclude-file "${SCRIPT_DIR}/.backup_ignore" 2>&1 | tee -a "$LOG_FILE"

# 5. Apply Retention Policy (Pruning)
log "INFO" "Applying retention policy..."
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --prune 2>&1 | tee -a "$LOG_FILE"

# 6. Check Repository Integrity
log "INFO" "Verifying repository..."
restic check 2>&1 | tee -a "$LOG_FILE"

log "SUCCESS" "Backup cycle complete."
