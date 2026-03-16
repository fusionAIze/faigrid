#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Edge Node Uninstaller
# ==============================================================================
set -euo pipefail

echo "[nexus-edge] Uninstalling Edge stack..."

if command -v caddy &> /dev/null; then
    echo "[nexus-edge] Removing Caddy service..."
    sudo systemctl stop caddy || true
    sudo apt-get remove --purge -y caddy
fi

echo "[nexus-edge] Resetting UFW..."
sudo ufw reset --force || true

echo "[nexus-edge] Edge node uninstalled."
