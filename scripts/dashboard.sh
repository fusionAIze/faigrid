#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Control Center Dashboard
# ==============================================================================
# Renders a terminal ASCII dashboard and/or a static HTML page showing node telemetry.
set -euo pipefail

MODE="shell"
if [[ "${1:-}" == "--html" ]]; then
    MODE="html"
fi

HTML_OUT="/var/www/nexus/index.html"
LOG_FILE="/var/log/nexus/nexus-system.log"

get_telemetry() {
    # Uptime
    UPTIME=$(uptime -p || echo "Unknown uptime")
    
    # CPU
    if command -v mpstat >/dev/null 2>&1; then
        CPU=$(mpstat 1 1 | awk '/Average/ {print 100-$12"%"}')
    else
        CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}' || echo "N/A")
    fi
    
    # RAM
    if [[ "$(uname -s)" == "Darwin" ]]; then
        RAM_USED=$(vm_stat | awk '/Pages active/ {print $3}' | tr -d '.')
        RAM_USED=$((RAM_USED * 4096 / 1024 / 1024))
        RAM="${RAM_USED} MB Active"
    else
        RAM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}' || echo "N/A")
    fi
    
    # Disk
    DISK=$(df -h / | tail -1 | awk '{print $5}' || echo "N/A")
    
    # Service parsing
    N8N_STATUS="DOWN"
    PG_STATUS="DOWN"
    CADDY_STATUS="DOWN"
    
    if curl -sSf -m 1 "http://127.0.0.1:5678/healthz" > /dev/null 2>&1; then N8N_STATUS="UP"; fi
    if command -v nc >/dev/null && nc -z -w 1 127.0.0.1 5432 2>/dev/null; then PG_STATUS="UP"; fi
    if curl -sSf -m 1 "http://127.0.0.1:2019/config/" > /dev/null 2>&1; then CADDY_STATUS="UP"; fi
}

if [[ "$MODE" == "shell" ]]; then
    get_telemetry
    
    echo "============================================================"
    echo "           fusionAIze Nexus Labs - Control Center           "
    echo "============================================================"
    echo " UPTIME : $UPTIME"
    echo " CPU    : $CPU"
    echo " RAM    : $RAM"
    echo " DISK   : $DISK"
    echo "------------------------------------------------------------"
    echo -e " n8n Core         : \t$N8N_STATUS"
    echo -e " PostgreSQL       : \t$PG_STATUS"
    echo -e " Caddy Edge       : \t$CADDY_STATUS"
    echo "============================================================"
    if [[ -f "$LOG_FILE" ]]; then
        echo " Recent System Events:"
        tail -n 5 "$LOG_FILE"
    else
        echo " (No telemetry logs found at $LOG_FILE)"
    fi
    echo "============================================================"
    
elif [[ "$MODE" == "html" ]]; then
    get_telemetry
    
    # Ensure dir
    sudo mkdir -p "$(dirname "$HTML_OUT")" 2>/dev/null || true
    sudo chmod 755 "$(dirname "$HTML_OUT")" 2>/dev/null || true
    
    LAST_EVENTS=""
    if [[ -f "$LOG_FILE" ]]; then
        LAST_EVENTS=$(tail -n 12 "$LOG_FILE" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
    fi
    
    cat <<EOF > /tmp/nexus-dashboard.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="30">
    <title>Nexus Labs Dashboard</title>
    <style>
        body { font-family: 'Courier New', Courier, monospace; background-color: #0f172a; color: #38bdf8; padding: 20px; line-height: 1.6; }
        .card { background-color: #1e293b; padding: 25px; border-radius: 8px; margin-bottom: 20px; }
        h1 { color: #f8fafc; border-bottom: 1px solid #475569; padding-bottom: 10px; margin-top: 0; }
        h2 { color: #f1f5f9; margin-top: 0; }
        .up { color: #4ade80; font-weight: bold; background: #064e3b; padding: 2px 8px; border-radius: 4px; }
        .down { color: #f87171; font-weight: bold; background: #7f1d1d; padding: 2px 8px; border-radius: 4px; }
        pre { background: #0b0f19; padding: 15px; overflow-x: auto; border: 1px solid #334155; border-radius: 6px; }
        .metric { display: grid; grid-template-columns: 150px 1fr; margin-bottom: 8px; }
    </style>
</head>
<body>
    <h1>fusionAIze Nexus Labs</h1>
    
    <div class="card">
        <h2>Hardware Telemetry</h2>
        <div class="metric"><strong>Uptime:</strong> <span>$UPTIME</span></div>
        <div class="metric"><strong>CPU Load:</strong> <span>$CPU</span></div>
        <div class="metric"><strong>RAM Usage:</strong> <span>$RAM</span></div>
        <div class="metric"><strong>Root Disk:</strong> <span>$DISK</span></div>
    </div>
    
    <div class="card">
        <h2>Service Endpoints</h2>
        <div class="metric"><strong>n8n Core:</strong> <span class="${N8N_STATUS,,}">$N8N_STATUS</span></div>
        <div class="metric"><strong>PostgreSQL:</strong> <span class="${PG_STATUS,,}">$PG_STATUS</span></div>
        <div class="metric"><strong>Caddy Edge:</strong> <span class="${CADDY_STATUS,,}">$CADDY_STATUS</span></div>
    </div>
    
    <div class="card">
        <h2>Aggregated Telemetry Log</h2>
        <pre>$LAST_EVENTS</pre>
    </div>
</body>
</html>
EOF

    sudo mv /tmp/nexus-dashboard.html "$HTML_OUT" 2>/dev/null || true
    sudo chmod 644 "$HTML_OUT" 2>/dev/null || true
fi
