#!/usr/bin/env bash
set -euo pipefail

# nexus-edge: apply a minimal LAN-only UFW ruleset for Pi-hole + optional HTTPS.
# - Deny incoming by default
# - Allow SSH (22), DNS (53 tcp/udp), HTTP (80), HTTPS (443) from LAN only
#
# Defaults are tailored for typical FRITZ!Box home LANs.
# Override via env vars:
#   IPV4_LAN_CIDR="192.168.178.0/24" IPV6_ULA_CIDR="fdaf:a57b:d3e6:0::/64" ./ufw-apply.sh

IPV4_LAN_CIDR="${IPV4_LAN_CIDR:-192.168.178.0/24}"
IPV6_ULA_CIDR="${IPV6_ULA_CIDR:-}"

echo "[nexus-edge] Applying UFW baseline..."
echo "  IPV4_LAN_CIDR=${IPV4_LAN_CIDR}"
echo "  IPV6_ULA_CIDR=${IPV6_ULA_CIDR:-<auto-detect>}"

# Ensure UFW is present
command -v ufw >/dev/null 2>&1 || { echo "ufw not found. Install: sudo apt-get install -y ufw"; exit 1; }

# Auto-detect ULA /64 from the first global fd.. address on eth0 if not provided
if [[ -z "${IPV6_ULA_CIDR}" ]]; then
  # Grab the first ULA IPv6 (fdxx:...) on eth0 and convert to /64
  ULA_ADDR="$(ip -6 addr show dev eth0 | awk '/inet6 fd/ {print $2; exit}' | cut -d/ -f1 || true)"
  if [[ -n "${ULA_ADDR}" ]]; then
    # Keep first 4 hextets (e.g. fdaf:a57b:d3e6:0) -> /64
    PREFIX="$(echo "${ULA_ADDR}" | awk -F: '{print $1":"$2":"$3":"$4}')"
    IPV6_ULA_CIDR="${PREFIX}::/64"
  fi
fi

echo "[nexus-edge] Resetting UFW..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

echo "[nexus-edge] Allow IPv4 LAN services..."
sudo ufw allow from "${IPV4_LAN_CIDR}" to any port 22 proto tcp
sudo ufw allow from "${IPV4_LAN_CIDR}" to any port 53 proto udp
sudo ufw allow from "${IPV4_LAN_CIDR}" to any port 53 proto tcp
sudo ufw allow from "${IPV4_LAN_CIDR}" to any port 80 proto tcp
sudo ufw allow from "${IPV4_LAN_CIDR}" to any port 443 proto tcp

if [[ -n "${IPV6_ULA_CIDR}" ]]; then
  echo "[nexus-edge] Allow IPv6 ULA LAN services..."
  sudo ufw allow from "${IPV6_ULA_CIDR}" to any port 22 proto tcp
  sudo ufw allow from "${IPV6_ULA_CIDR}" to any port 53 proto udp
  sudo ufw allow from "${IPV6_ULA_CIDR}" to any port 53 proto tcp
  sudo ufw allow from "${IPV6_ULA_CIDR}" to any port 80 proto tcp
  sudo ufw allow from "${IPV6_ULA_CIDR}" to any port 443 proto tcp
else
  echo "[warn] No IPv6 ULA detected. IPv6 LAN rules not applied."
  echo "       Set IPV6_ULA_CIDR manually if needed."
fi

echo "[nexus-edge] Enabling UFW..."
sudo ufw --force enable
sudo ufw status verbose

echo "[nexus-edge] Done."
