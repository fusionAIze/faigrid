#!/usr/bin/env bash
set -euo pipefail
echo "[nexus-backup] Updating backup tools..."
if command -v restic &> /dev/null; then
    sudo restic self-update || true
fi
echo "[nexus-backup] Update complete."
