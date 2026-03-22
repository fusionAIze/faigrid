#!/usr/bin/env bash
set -euo pipefail
echo "[grid-backup] Verifying backup status..."

if command -v restic &> /dev/null; then
    echo "[SUCCESS] Restic is installed."
else
    echo "[WARN] Restic is not installed."
fi

df -h | grep -i "backup" || echo "[INFO] No dedicated backup partitions detected."
