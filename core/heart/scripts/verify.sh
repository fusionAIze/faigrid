echo "── nexus-core / Docker Services ──"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "── nexus-core / n8n ──"
N8N_VERSION=$(docker exec nexus-n8n n8n --version 2>/dev/null || echo "unknown")
echo "  Version : ${N8N_VERSION}"
curl -fsS http://127.0.0.1:5678/ >/dev/null && echo "  Status  : ✔ Reachable on localhost:5678" || echo "  Status  : ✘ Not reachable"

# Trigger OpenClaw verification if present
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &> /dev/null && pwd)"
if [[ -d "${CORE_DIR}/openclaw" ]]; then
    echo ""
    echo "── nexus-core / OpenClaw ──"
    bash "${CORE_DIR}/openclaw/scripts/verify.sh"
fi

echo ""
echo "── nexus-core / System ──"
echo -n "  Disk    : "
df -h / | tail -n 1 | awk '{print $3 " / " $2 " (" $5 " used)"}'
echo -n "  Uptime  : "
uptime -p
