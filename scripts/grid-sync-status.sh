#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Core to External Status Sync
# ==============================================================================
set -euo pipefail

# This script is intended to be called by nexus-watchdog.sh on the Core node.
# It pushes the current grid status JSON to the external dashboard.

LOCAL_STATUS="/var/www/nexus/grid-status.json"
REMOTE_TARGET="$(grep "ROLE=external" .env.topology -B 5 | grep "SSH_TARGET" | cut -d'=' -f2 || echo "")"

# Ensure we are in the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd || exit 1)"
cd "${SCRIPT_DIR}/.." || exit 1

if [[ -z "$REMOTE_TARGET" ]]; then
    echo "[nexus-sync] No external target configured in .env.topology. Skipping sync."
    exit 0
fi

if [[ -f "$LOCAL_STATUS" ]]; then
    echo "[nexus-sync] Pushing grid status to ${REMOTE_TARGET}..."
    scp -q "$LOCAL_STATUS" "${REMOTE_TARGET}:/var/www/nexus/grid-status.json"
    
    # Trigger dashboard refresh on remote
    ssh -q "$REMOTE_TARGET" "bash /tmp/nexus-install/external/scripts/grid-external-dashboard.sh"
else
    echo "[nexus-sync] Local status file not found: ${LOCAL_STATUS}"
fi
