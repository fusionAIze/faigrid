#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Edge Node Uninstaller
# ==============================================================================
set -euo pipefail

echo "[grid-edge] Uninstalling Edge stack..."

if command -v caddy &> /dev/null; then
    echo "[grid-edge] Removing Caddy service..."
    sudo systemctl stop caddy || true
    sudo apt-get remove --purge -y caddy
fi

echo "[grid-edge] Resetting UFW..."
sudo ufw reset --force || true

echo "[grid-edge] Edge node uninstalled."
