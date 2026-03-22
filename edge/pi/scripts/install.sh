#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Edge Node Installer
# ==============================================================================
set -euo pipefail

echo "[grid-edge] Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y ufw curl ca-certificates

echo "[grid-edge] Applying security baseline..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd || exit 1)"

if [[ -f "${SCRIPT_DIR}/ufw-apply.sh" ]]; then
    bash "${SCRIPT_DIR}/ufw-apply.sh"
else
    echo "[WARN] ufw-apply.sh not found in ${SCRIPT_DIR}"
fi

# Optional: Add Caddy installation here if not already present
if ! command -v caddy &> /dev/null; then
    echo "[grid-edge] Installing Caddy Proxy..."
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update
    sudo apt install caddy
fi

echo "[grid-edge] Node installation and hardening complete."
