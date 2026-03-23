#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${1:-}"
DISPLAY_NUM="${2:-}"

if [[ -z "${USER_NAME}" || -z "${DISPLAY_NUM}" ]]; then
  echo "Usage: $0 <user> <display>"
  echo "Example: $0 grid-ops 1"
  exit 1
fi

echo "[core] configuring VNC for user=${USER_NAME} display=:${DISPLAY_NUM}"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_SRC="${SRC_DIR}/configs/systemd-user/vncserver@.service"
TIGER_CONF_SRC="${SRC_DIR}/configs/tigervnc/config.example"

# Ensure runtime dirs
sudo -u "${USER_NAME}" mkdir -p "/home/${USER_NAME}/.config/systemd/user" "/home/${USER_NAME}/.config/tigervnc"

# Install user systemd unit
sudo install -m 0644 "${UNIT_SRC}" "/home/${USER_NAME}/.config/systemd/user/vncserver@.service"
sudo chown "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/.config/systemd/user/vncserver@.service"

# Install tigervnc config (example -> active config)
sudo install -m 0644 "${TIGER_CONF_SRC}" "/home/${USER_NAME}/.config/tigervnc/config"
sudo chown "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/.config/tigervnc/config"

# Enable linger so user services can run without active login
sudo loginctl enable-linger "${USER_NAME}" || true

echo
echo "[core] next manual step (per user): set VNC password"
echo "  sudo -u ${USER_NAME} vncpasswd"
echo
echo "[core] after setting password, enable service:"
echo "  sudo -u ${USER_NAME} XDG_RUNTIME_DIR=/run/user/\$(id -u ${USER_NAME}) systemctl --user daemon-reload"
echo "  sudo -u ${USER_NAME} XDG_RUNTIME_DIR=/run/user/\$(id -u ${USER_NAME}) systemctl --user enable --now vncserver@${DISPLAY_NUM}.service"
echo
echo "[core] done"
