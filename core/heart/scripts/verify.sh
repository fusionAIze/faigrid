#!/usr/bin/env bash
set -euo pipefail

echo "── grid-core / Docker Services ──"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "── grid-core / n8n ──"
N8N_VERSION=$(docker exec grid-core-n8n n8n --version 2>/dev/null || echo "unknown")
echo "  Version : ${N8N_VERSION}"

# Detect container state: Restarting, starting up, or settled
_n8n_state=$(docker inspect --format '{{.State.Status}}' grid-core-n8n 2>/dev/null || echo "unknown")
_n8n_started=$(docker inspect --format '{{.State.StartedAt}}' grid-core-n8n 2>/dev/null || echo "")
_n8n_uptime_s=9999
if [[ -n "$_n8n_started" ]]; then
    _now=$(date -u +%s)
    _start=$(date -u -d "$_n8n_started" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S" "${_n8n_started%%.*}" +%s 2>/dev/null || echo "$_now")
    _n8n_uptime_s=$(( _now - _start ))
fi

if [[ "$_n8n_state" == "restarting" ]]; then
    echo "  Status  : ✘ Container is crash-looping — showing last logs:"
    docker logs grid-core-n8n --tail 15 2>&1 | sed 's/^/    /'
elif curl -fsS --max-time 3 http://127.0.0.1:5678/ >/dev/null 2>&1; then
    echo "  Status  : ✔ Reachable on localhost:5678"

    # Smart Connectivity Hint
    TOPOLOGY_FILE="/tmp/grid-install/.env.topology"
    if [[ ! -f "$TOPOLOGY_FILE" ]]; then TOPOLOGY_FILE="$(dirname "${BASH_SOURCE[0]}")/../../../../.env.topology"; fi

    if [[ -f "$TOPOLOGY_FILE" ]]; then
        EDGE_TARGET=$(grep "^EDGE_TARGET=" "$TOPOLOGY_FILE" | cut -d'=' -f2 || echo "")
        if [[ -n "$EDGE_TARGET" ]]; then
            echo "  Access  : ℹ Proxied via grid-edge ($EDGE_TARGET)"
            echo "            Check your browser at: https://n8n.your-domain.com"
        else
            echo "  Access  : ⚠ No Edge Proxy detected. Use SSH Tunnel for browser access:"
            echo "            ssh -L 5678:localhost:5678 $(whoami)@$(hostname -I | awk '{print $1}')"
        fi
    fi
elif [[ "$_n8n_uptime_s" -lt 45 ]]; then
    echo "  Status  : ⏳ Starting up (${_n8n_uptime_s}s) — re-verify in ~$((45 - _n8n_uptime_s))s"
else
    echo "  Status  : ✘ Not reachable — run 'Control → Reload' or check logs"
fi

# Trigger OpenClaw verification if present
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &> /dev/null && pwd)"
if [[ -d "${CORE_DIR}/openclaw" ]]; then
    echo ""
    echo "── grid-core / OpenClaw ──"
    bash "${CORE_DIR}/openclaw/scripts/verify.sh"
fi

# Workbench summary
if [[ -d "${CORE_DIR}/workbench" ]]; then
    echo ""
    echo -n "── grid-core / Workbench : "
    bash "${CORE_DIR}/workbench/scripts/control.sh" summary 2>/dev/null || echo "not accessible"
fi

echo ""
echo "── grid-core / System ──"
echo -n "  Disk    : "
df -h / | tail -n 1 | awk '{print $3 " / " $2 " (" $5 " used)"}'
echo -n "  Uptime  : "
uptime -p
