#!/usr/bin/env bash
set -euo pipefail

# grid-edge: minimal maintenance update
# - apt update/upgrade
# - optional: update Pi-hole
# - show health summary

DO_PIHOLE_UPDATE="${DO_PIHOLE_UPDATE:-0}"

echo "[grid-edge] updating apt package lists..."
sudo apt-get update

echo "[grid-edge] upgrading packages (non-interactive)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "[grid-edge] autoremove..."
sudo apt-get autoremove -y

if [[ "${DO_PIHOLE_UPDATE}" == "1" ]]; then
  echo "[grid-edge] updating Pi-hole subsystems..."
  sudo pihole -up
else
  echo "[grid-edge] skipping Pi-hole subsystem update (set DO_PIHOLE_UPDATE=1 to enable)"
fi

echo
echo "[grid-edge] status summary"
echo "hostname: $(hostname)"
echo "uptime  : $(uptime -p || true)"
echo

echo "[grid-edge] ufw"
sudo ufw status verbose | sed -n '1,120p' || true
echo

echo "[grid-edge] pihole"
pihole status || true
echo

echo "[grid-edge] listening ports (22/53/80/443)"
sudo ss -tulpn | egrep ':22|:53|:80|:443' || true
echo

echo "[grid-edge] disk usage"
df -h / | tail -n 1 || true

echo "[grid-edge] done"
