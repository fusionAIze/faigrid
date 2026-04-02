#!/usr/bin/env bash
# grid-messenger install — runs on the core node
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/grid-messenger"
CONFIG_DIR="/etc/grid-messenger"
SERVICE_USER="grid-messenger"

echo "[grid-messenger] Installing prerequisites…"
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv

echo "[grid-messenger] Creating system user '${SERVICE_USER}'…"
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    sudo useradd -r -s /usr/sbin/nologin -M "$SERVICE_USER"
fi

echo "[grid-messenger] Creating directories…"
sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$CONFIG_DIR"

echo "[grid-messenger] Copying source…"
sudo cp "${SCRIPT_DIR}/src/grid_messenger.py" "$INSTALL_DIR/grid_messenger.py"

echo "[grid-messenger] Creating Python virtual environment…"
sudo python3 -m venv "$INSTALL_DIR/venv"
sudo "$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
sudo "$INSTALL_DIR/venv/bin/pip" install --quiet \
    "python-telegram-bot>=20.0" \
    "aiohttp>=3.9"

echo "[grid-messenger] Setting ownership…"
sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
sudo chown root:"$SERVICE_USER" "$CONFIG_DIR"
sudo chmod 750 "$CONFIG_DIR"

echo "[grid-messenger] Creating config template…"
if [[ ! -f "${CONFIG_DIR}/config.env" ]]; then
    sudo tee "${CONFIG_DIR}/config.env" > /dev/null << 'EOF'
# fusionAIze Grid Messenger — Configuration
# Edit with: sudo nano /etc/grid-messenger/config.env
# Then restart: sudo systemctl restart grid-messenger

# Required: get from @BotFather on Telegram
TELEGRAM_BOT_TOKEN=

# Your Telegram user ID (find via @userinfobot)
TELEGRAM_ALLOWED_USER_IDS=

# Chat IDs for proactive notifications (defaults to ALLOWED_USER_IDS)
NOTIFY_CHAT_IDS=

# Core service URLs (default: localhost)
N8N_BASE_URL=http://127.0.0.1:5678
FAIGATE_URL=http://127.0.0.1:8090
OPENCLAW_URL=http://127.0.0.1:18789

# Inbound HTTP port (for n8n → grid-messenger approval requests)
WEBHOOK_PORT=9119
WEBHOOK_BIND=127.0.0.1
EOF
    sudo chown root:"$SERVICE_USER" "${CONFIG_DIR}/config.env"
    sudo chmod 640 "${CONFIG_DIR}/config.env"
    echo "[grid-messenger] Config template created at ${CONFIG_DIR}/config.env"
fi

echo "[grid-messenger] Installing systemd service…"
sudo cp "${SCRIPT_DIR}/systemd/grid-messenger.service" \
    /etc/systemd/system/grid-messenger.service
sudo systemctl daemon-reload
sudo systemctl enable grid-messenger.service

echo ""
echo "[grid-messenger] Installed."
echo "  Next: configure via faigrid workbench → grid-messenger → Configure"
echo "  Or:   sudo nano ${CONFIG_DIR}/config.env"
echo "        sudo systemctl start grid-messenger"
