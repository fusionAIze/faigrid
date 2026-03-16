#!/usr/bin/env bash
set -euo pipefail
echo "[nexus-edge] Verifying Caddy..."
if systemctl is-active --quiet caddy; then
    echo "[SUCCESS] Caddy service is running."
else
    echo "[ERROR] Caddy service is NOT running."
fi
echo "[nexus-edge] Verifying UFW..."
sudo ufw status verbose
