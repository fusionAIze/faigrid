#!/usr/bin/env bash
# grid-messenger update — replace Python source and restart
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/grid-messenger"

echo "[grid-messenger] Updating source…"
sudo cp "${SCRIPT_DIR}/src/grid_messenger.py" "$INSTALL_DIR/grid_messenger.py"

echo "[grid-messenger] Updating Python dependencies…"
sudo "$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade \
    "python-telegram-bot>=20.0" \
    "aiohttp>=3.9"

echo "[grid-messenger] Restarting service…"
sudo systemctl restart grid-messenger.service
sudo systemctl --no-pager status grid-messenger.service | head -8

echo "[grid-messenger] Update complete."
