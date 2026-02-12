#!/usr/bin/env bash
set -euo pipefail

echo "[core] applying ssh hardening..."

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_SRC="${SRC_DIR}/configs/sshd_config.d/10-nexus.conf"
CONF_DST="/etc/ssh/sshd_config.d/10-nexus.conf"

sudo install -m 0644 "${CONF_SRC}" "${CONF_DST}"

echo "[core] validating sshd config..."
sudo sshd -t

echo "[core] restarting sshd..."
sudo systemctl restart ssh

echo "[core] effective sshd settings:"
sudo sshd -T | egrep -i 'permitrootlogin|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|pubkeyauthentication|allowusers|maxauthtries|logingracetime' || true

echo "[core] done"
