#!/usr/bin/env bash
set -euo pipefail

echo "[verify] uptime:"
uptime || true

echo
echo "[verify] hostname:"
hostname || true

echo
echo "[verify] ipv4:"
ip -4 addr show | sed -n '1,120p' || true

echo
echo "[verify] sshd effective config (key items):"
sudo sshd -T | egrep -i 'permitrootlogin|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|pubkeyauthentication|allowusers|maxauthtries|logingracetime' || true

echo
echo "[verify] ufw:"
sudo ufw status verbose || true

echo
echo "[verify] listening VNC ports (should be localhost only):"
sudo ss -tulpn | egrep ':590[0-9]' || true

echo
echo "[verify] done"
