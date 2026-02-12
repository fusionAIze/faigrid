#!/usr/bin/env bash
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.178.0/24}"

echo "[core] applying ufw baseline (LAN_CIDR=${LAN_CIDR})"

sudo apt-get update
sudo apt-get install -y ufw

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH from LAN
sudo ufw allow from "${LAN_CIDR}" to any port 22 proto tcp

# Note: VNC is expected via SSH tunnel -> keep VNC ports closed on the firewall.

sudo ufw --force enable
sudo ufw status verbose
