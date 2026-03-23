#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Interactive Restore Navigator
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd || exit 1)"

# 1. Load Config
CONFIG_FILE="${SCRIPT_DIR}/_backup_config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[grid-restore] [ERROR] Configuration file missing: ${CONFIG_FILE}"
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

echo "============================================================"
echo "          fusionAIze Grid - Snapshot Restore Navigator           "
echo "============================================================"

# List snapshots
restic snapshots

echo ""
read -r -p "Enter Snapshot ID to restore (or 'browse' to mount): " SNAPSHOT_ID

if [[ -z "$SNAPSHOT_ID" ]]; then
    echo "Aborted."
    exit 0
fi

if [[ "$SNAPSHOT_ID" == "browse" ]]; then
    MOUNT_POINT="/mnt/grid-recovery"
    sudo mkdir -p "$MOUNT_POINT"
    echo "Mounting repository to ${MOUNT_POINT}..."
    echo "Keep this terminal open. Press Ctrl+C to unmount when done."
    sudo restic mount "$MOUNT_POINT"
    exit 0
fi

read -r -p "Target directory for restoration (Default: /tmp/grid-restored): " RESTORE_TARGET
RESTORE_TARGET="${RESTORE_TARGET:-/tmp/grid-restored}"

mkdir -p "$RESTORE_TARGET"
echo "Restoring snapshot ${SNAPSHOT_ID} to ${RESTORE_TARGET}..."
restic restore "$SNAPSHOT_ID" --target "$RESTORE_TARGET"

echo "RESTORE COMPLETE."
echo "Note: You may need to manually move files or re-import database dumps from the restored folder."
