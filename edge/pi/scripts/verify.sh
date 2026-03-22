#!/usr/bin/env bash
# grid-edge: verify.sh — Read-only health check for the Edge node
# Caddy is OPTIONAL on edge (used as internal LAN proxy; not required if
# all external traffic is handled by grid-external).
set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✔${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✘${NC}  $1"; }
section() { echo ""; echo -e "${DIM}── $1 ──${NC}"; }

section "grid-edge / Services"

# --- Pi-hole ---
if command -v pihole &>/dev/null; then
    # Version 6+ check: is FTL running and listening?
    if pgrep -x "pihole-FTL" &>/dev/null || pihole status 2>/dev/null | grep -qE "Active|listening"; then
        ok "Pi-hole: active (pihole-FTL detected)"
    else
        warn "Pi-hole: installed but service seems inactive"
    fi
else
    # Fallback: check if the process is there even if binary isn't in PATH (unlikely but safer)
    if pgrep -x "pihole-FTL" &>/dev/null; then
        ok "Pi-hole: active (detected via process list)"
    else
        fail "Pi-hole: not found"
    fi
fi

# --- Caddy (OPTIONAL) ---
if command -v caddy &>/dev/null || pgrep -x caddy &>/dev/null || [ -f "/usr/bin/caddy" ]; then
    if systemctl is-active --quiet caddy 2>/dev/null || pgrep -x caddy &>/dev/null; then
        ok "Caddy: running (internal LAN proxy mode)"
    else
        warn "Caddy: found but not running — likely port conflict with Pi-hole (80/443)"
    fi
else
    warn "Caddy: not installed — optional for internal LAN proxying"
fi

# --- UFW Firewall ---
section "grid-edge / Firewall (UFW)"
if command -v ufw &>/dev/null; then
    if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        ok "UFW: active"
        sudo ufw status verbose | sed -n '1,60p'
    else
        fail "UFW: inactive — firewall is not protecting this node"
    fi
else
    fail "UFW: not installed"
fi

# --- Network ---
section "grid-edge / Listening Ports"
echo -e "  ${DIM}Expecting: 22 (SSH), 53 (DNS), 80/443 (optional Caddy)${NC}"
sudo ss -tulpn 2>/dev/null | grep -E ':22|:53|:80|:443' || echo "  (none of the expected ports are listening)"

# --- Disk ---
section "grid-edge / Disk Usage"
df -h / | tail -n 1

# --- System ---
section "grid-edge / System"
echo "  Hostname : $(hostname)"
echo "  Uptime   : $(uptime -p 2>/dev/null || uptime)"
echo "  OS       : $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -sr)"

echo ""
ok "grid-edge verify complete"
