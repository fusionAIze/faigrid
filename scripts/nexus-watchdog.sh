#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - System Watchdog
# ==============================================================================
# Triggered via systemd timer to ping Edge, Core, and Database services.
# Emits standardized telemetry to the Centralized Logging endpoint.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LIB_PATH="${SCRIPT_DIR}/../core/workbench/scripts/_lib.sh"

if [[ -f "$LIB_PATH" ]]; then
    # shellcheck source=core/workbench/scripts/_lib.sh
    source "$LIB_PATH"
else
    # Fallback local definition if standalone
    log_event() { 
       echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | ${1} | [${2}] | ${3}" 
    }
fi

log_event "watchdog" "INFO" "Watchdog health cycle initiated."

# 1. Check n8n Core
if curl -sSf -m 3 "http://127.0.0.1:5678/healthz" > /dev/null 2>&1; then
    log_event "watchdog" "INFO" "Service 'n8n' (Nexus Core) is healthy."
else
    log_event "watchdog" "ERROR" "Service 'n8n' failed healthcheck on port 5678."
fi

# 2. Check PostgreSQL Database
if command -v nc > /dev/null && nc -z -w 3 127.0.0.1 5432 2>/dev/null; then
    log_event "watchdog" "INFO" "Service 'PostgreSQL' port 5432 is responding."
else
    log_event "watchdog" "WARN" "Service 'PostgreSQL' is unreachable at 127.0.0.1:5432. (Ignored if not a Core node)."
fi

# 3. Check Edge (Caddy admin API)
if curl -sSf -m 3 "http://127.0.0.1:2019/config/" > /dev/null 2>&1; then
    log_event "watchdog" "INFO" "Service 'Caddy' (Nexus Edge) is responding."
else
    log_event "watchdog" "WARN" "Service 'Caddy' proxy not detected on port 2019. (Ignored if not an Edge node)."
fi

# 4. Generate Static HTML Dashboard Component
if [[ -x "${SCRIPT_DIR}/dashboard.sh" ]]; then
    "${SCRIPT_DIR}/dashboard.sh" --html
fi

log_event "watchdog" "INFO" "Watchdog health cycle complete."
