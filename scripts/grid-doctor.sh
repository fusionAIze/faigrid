#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Grid Doctor (Diagnostics)
# ==============================================================================
# Comprehensive sanity checks for the 5-node architecture.
# Usage: ./grid-doctor.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd || exit 1)"
LIB_PATH="${SCRIPT_DIR}/../core/workbench/scripts/_lib.sh"

if [[ -f "$LIB_PATH" ]]; then
    # shellcheck source=core/workbench/scripts/_lib.sh
    source "$LIB_PATH"
else
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_CYAN='\033[0;36m'; C_RESET='\033[0m'
    info() { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
    success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $*"; }
    error() { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }
fi

print_header "Grid Doctor: Infrastructure Diagnostics"

# Free-memory helpers. Both return a whole number (MB) so downstream integer
# arithmetic never trips `[[ ... -lt ... ]]`. The Darwin helper reads the real
# page size from the vm_stat header instead of assuming 4096.
_free_mb_darwin() {
    vm_stat | awk '
        /page size of/ { gsub(/[^0-9]/, "", $0); ps = $0 }
        /Pages free/ { gsub(/\./, "", $3); f = $3 }
        /Pages inactive/ { gsub(/\./, "", $3); i = $3 }
        END { printf "%.0f", (f + i) * ps / 1048576 }'
}

_free_mb_linux() {
    free -m | awk '/^Mem:/{print $4}'
}

_memory_status() {
    local mb="$1"
    if [[ "$mb" -lt 512 ]]; then
        warn "Low memory detected: ${mb}MB free. Core services might be unstable."
    else
        success "Memory: ${mb}MB free."
    fi
}

# Count JSONL log lines carrying "severity":"ERROR". Returns exactly one integer:
# grep -c prints "0" and exits 1 on zero matches, so `|| true` suppresses the
# failure without appending a second value, and the regex guard normalizes any
# unexpected/empty result (e.g. a missing file) back to 0.
_count_log_errors() {
    local file="$1"
    local count
    count=$(grep -c '"severity":"ERROR"' "$file" 2>/dev/null || true)
    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        count=0
    fi
    printf '%s\n' "$count"
}

# 1. Environment & Resources
info "Checking system resources..."
if [[ "$(uname -s)" == "Darwin" ]]; then
    FREE_MB=$(_free_mb_darwin)
    DISK_PCT=$(df -k / | tail -1 | awk '{print $5}' | sed 's/%//')
else
    FREE_MB=$(_free_mb_linux)
    DISK_PCT=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
fi

_memory_status "$FREE_MB"

if [[ "$DISK_PCT" -gt 90 ]]; then
    error "Disk nearly full: ${DISK_PCT}% used!"
else
    success "Disk: ${DISK_PCT}% used."
fi

# 2. Network Internal & External
info "Testing connectivity..."
if ping -c 1 1.1.1.1 &> /dev/null; then
    success "Internet connectivity: OK"
else
    error "No internet access detected."
fi

# 3. Docker & Service Status
info "Auditing service stack..."
if command -v docker &> /dev/null; then
    if sudo docker ps &> /dev/null; then
        success "Docker Engine: Running"
        
        # Check Core containers
        if sudo docker ps | grep -q "grid-core-n8n"; then
            success "Core service: n8n is running."
        fi
    else
        error "Docker daemon is NOT responding. Try: sudo systemctl restart docker"
    fi
else
    info "Docker not found (Standard behavior for Edge/Mac-Worker nodes)."
fi

# 4. State Verification (read-only: grid-doctor never writes state)
STATE_DIR="${HOME}/.config/faigrid/registry"
STATE_FILE="${STATE_DIR}/state.env"
LEGACY_STATE="${HOME}/.grid-state"
CURRENT_ROLE=""
if [[ -f "$STATE_FILE" ]]; then
    CURRENT_ROLE=$(grep "GRID_ROLE=" "$STATE_FILE" | cut -d= -f2 || echo "unknown")
    # Fall back to ROLE= key written by older canonical versions
    if [[ -z "$CURRENT_ROLE" || "$CURRENT_ROLE" == "unknown" ]]; then
        CURRENT_ROLE=$(grep "ROLE=" "$STATE_FILE" | cut -d= -f2 || echo "unknown")
    fi
    success "Node identity verified: Role is [${CURRENT_ROLE}]."
elif [[ -f "$LEGACY_STATE" ]]; then
    warn "Legacy ~/.grid-state found; run faigrid install to migrate."
else
    warn "No state registry found. This node may be unprovisioned."
fi

# 5. Log Health
LOG_FILE="${LOG_FILE:-/var/log/faigrid/grid-system.log}"
if [[ -f "$LOG_FILE" ]]; then
    ERR_COUNT=$(_count_log_errors "$LOG_FILE")
    if [[ "$ERR_COUNT" -gt 0 ]]; then
        warn "Found ${ERR_COUNT} error(s) in the system logs. Run: tail -n 20 ${LOG_FILE}"
    else
        success "System logs: Clean (0 errors recently)."
    fi
fi

echo -e "\n${C_BOLD}${C_CYAN}>>> Diagnosis Complete.<<<${C_RESET}\n"
