#!/usr/bin/env bash
set -euo pipefail
echo "[grid-backup] Updating backup tools..."
if command -v restic &> /dev/null; then
    sudo restic self-update || true
fi
echo "[grid-backup] Update complete."
