#!/usr/bin/env bash
set -euo pipefail

echo "── nexus-core / Docker Services ──"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "── nexus-core / n8n ──"
N8N_VERSION=$(docker exec nexus-n8n n8n --version 2>/dev/null || echo "unknown")
echo "  Version : ${N8N_VERSION}"
if curl -fsS http://127.0.0.1:5678/ >/dev/null 2>&1; then
    echo "  Status  : ✔ Reachable on localhost:5678"
    
    # Smart Connectivity Hint
    TOPOLOGY_FILE="/tmp/nexus-install/.env.topology"
    if [[ ! -f "$TOPOLOGY_FILE" ]]; then TOPOLOGY_FILE="$(dirname "${BASH_SOURCE[0]}")/../../../../.env.topology"; fi
    
    if [[ -f "$TOPOLOGY_FILE" ]]; then
        EDGE_TARGET=$(grep "^EDGE_TARGET=" "$TOPOLOGY_FILE" | cut -d'=' -f2 || echo "")
        if [[ -n "$EDGE_TARGET" ]]; then
            echo "  Access  : ℹ Proxied via nexus-edge ($EDGE_TARGET)"
            echo "            Check your browser at: https://n8n.your-domain.com"
        else
            echo "  Access  : ⚠ No Edge Proxy detected. Use SSH Tunnel for browser access:"
            echo "            ssh -L 5678:localhost:5678 $(whoami)@$(hostname -I | awk '{print $1}')"
        fi
    fi
else
    echo "  Status  : ✘ Not reachable (check 'Control -> reload')"
fi

# Trigger OpenClaw verification if present
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &> /dev/null && pwd)"
if [[ -d "${CORE_DIR}/openclaw" ]]; then
    echo ""
    echo "── nexus-core / OpenClaw ──"
    bash "${CORE_DIR}/openclaw/scripts/verify.sh"
fi

# Workbench summary
if [[ -d "${CORE_DIR}/workbench" ]]; then
    echo ""
    echo -n "── nexus-core / Workbench : "
    bash "${CORE_DIR}/workbench/scripts/control.sh" summary 2>/dev/null || echo "not accessible"
fi

echo ""
echo "── nexus-core / System ──"
echo -n "  Disk    : "
df -h / | tail -n 1 | awk '{print $3 " / " $2 " (" $5 " used)"}'
echo -n "  Uptime  : "
uptime -p
