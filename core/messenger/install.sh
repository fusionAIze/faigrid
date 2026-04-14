#!/usr/bin/env bash
# grid-messenger install — runs on the core node
# Supports: macOS (Homebrew / launchd) and Linux (systemd)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

# ── macOS (Homebrew / Solo Operator) ──────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then
    echo "[grid-messenger] macOS detected — using Homebrew + launchd setup"

    CONFIG_DIR="${HOME}/.config/grid-messenger"
    DATA_DIR="${HOME}/.local/share/grid-messenger"
    VENV_DIR="${DATA_DIR}/venv"
    PLIST="${HOME}/Library/LaunchAgents/ai.fusionaize.grid-messenger.plist"

    # Prefer brew-managed faigrid-messenger binary if available
    if command -v faigrid-messenger >/dev/null 2>&1; then
        MESSENGER_BIN="$(command -v faigrid-messenger)"
        VENV_PYTHON=""
        echo "[grid-messenger] Using Homebrew-managed faigrid-messenger binary"
    else
        # Fallback: standalone venv
        echo "[grid-messenger] faigrid-messenger not found — setting up standalone venv"
        MESSENGER_BIN=""
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --quiet --upgrade pip
        "$VENV_DIR/bin/pip" install --quiet \
            "python-telegram-bot>=20.0" \
            "aiohttp>=3.9"
        VENV_PYTHON="${VENV_DIR}/bin/python3"
    fi

    mkdir -p "$CONFIG_DIR" "$DATA_DIR"

    # Config template
    if [[ ! -f "${CONFIG_DIR}/config.env" ]]; then
        cat > "${CONFIG_DIR}/config.env" << 'EOF'
# fusionAIze Grid Messenger — Configuration
# Restart after editing: brew services restart faigrid

# Required: get from @BotFather on Telegram
TELEGRAM_BOT_TOKEN=

# Your Telegram user ID (find via @userinfobot)
TELEGRAM_ALLOWED_USER_IDS=

# Chat IDs for notifications (defaults to ALLOWED_USER_IDS)
NOTIFY_CHAT_IDS=

# Core service URLs
N8N_BASE_URL=http://127.0.0.1:5678
FAIGATE_URL=http://127.0.0.1:8090
OPENCLAW_URL=http://127.0.0.1:18789

# Inbound HTTP port
WEBHOOK_PORT=9119
WEBHOOK_BIND=127.0.0.1
APPS_FILE=
EOF
        # Fill in APPS_FILE path
        echo "APPS_FILE=${DATA_DIR}/apps.json" >> "${CONFIG_DIR}/config.env"
        chmod 600 "${CONFIG_DIR}/config.env"
        echo "[grid-messenger] Config template created at ${CONFIG_DIR}/config.env"
        echo "  → Edit it and add TELEGRAM_BOT_TOKEN + TELEGRAM_ALLOWED_USER_IDS"
    fi

    # LaunchAgent plist (only if not using brew services)
    if [[ -z "$MESSENGER_BIN" ]] && [[ ! -f "$PLIST" ]]; then
        cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.fusionaize.grid-messenger</string>
    <key>ProgramArguments</key>
    <array>
        <string>${VENV_PYTHON}</string>
        <string>${SCRIPT_DIR}/src/grid_messenger.py</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>APPS_FILE</key>
        <string>${DATA_DIR}/apps.json</string>
    </dict>
    <key>EnvironmentFiles</key>
    <array>
        <string>${CONFIG_DIR}/config.env</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${DATA_DIR}/grid-messenger.log</string>
    <key>StandardErrorPath</key>
    <string>${DATA_DIR}/grid-messenger.log</string>
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
</dict>
</plist>
PLIST_EOF
        echo "[grid-messenger] LaunchAgent created at ${PLIST}"
        echo "  → Start with: launchctl load ${PLIST}"
    fi

    echo ""
    echo "[grid-messenger] Installed (macOS)."
    if command -v faigrid-messenger >/dev/null 2>&1; then
        echo "  Start:   brew services start faigrid"
        echo "  Restart: brew services restart faigrid"
        echo "  Logs:    tail -f $(brew --prefix)/var/log/faigrid/messenger.log"
    else
        echo "  Edit config: ${CONFIG_DIR}/config.env"
        echo "  Start:       launchctl load ${PLIST}"
        echo "  Logs:        tail -f ${DATA_DIR}/grid-messenger.log"
    fi
    exit 0
fi

# ── Linux (systemd / grid-core node) ─────────────────────────────────────────
INSTALL_DIR="/opt/grid-messenger"
CONFIG_DIR="/etc/grid-messenger"
SERVICE_USER="grid-messenger"

echo "[grid-messenger] Linux detected — using systemd setup"

if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y -q
    sudo apt-get install -y -q python3 python3-pip python3-venv
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y -q python3 python3-pip
else
    echo "[grid-messenger] WARNING: unknown package manager — ensure python3 + venv are available"
fi

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
# Edit: sudo nano /etc/grid-messenger/config.env
# Restart: sudo systemctl restart grid-messenger

TELEGRAM_BOT_TOKEN=
TELEGRAM_ALLOWED_USER_IDS=
NOTIFY_CHAT_IDS=
N8N_BASE_URL=http://127.0.0.1:5678
FAIGATE_URL=http://127.0.0.1:8090
OPENCLAW_URL=http://127.0.0.1:18789
WEBHOOK_PORT=9119
WEBHOOK_BIND=127.0.0.1
APPS_FILE=/opt/grid-messenger/apps.json
EOF
    sudo chown root:"$SERVICE_USER" "${CONFIG_DIR}/config.env"
    sudo chmod 640 "${CONFIG_DIR}/config.env"
fi

echo "[grid-messenger] Installing systemd service…"
sudo cp "${SCRIPT_DIR}/systemd/grid-messenger.service" \
    /etc/systemd/system/grid-messenger.service
sudo systemctl daemon-reload
sudo systemctl enable grid-messenger.service

echo ""
echo "[grid-messenger] Installed (Linux)."
echo "  Configure: sudo nano ${CONFIG_DIR}/config.env"
echo "  Start:     sudo systemctl start grid-messenger"
echo "  Logs:      journalctl -u grid-messenger -f"
