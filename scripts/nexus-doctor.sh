#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Nexus Doctor (Diagnostics)
# ==============================================================================
# Comprehensive sanity checks for the 5-node architecture.
# Usage: ./nexus-doctor.sh
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

print_header "Nexus Doctor: Infrastructure Diagnostics"

# 1. Environment & Resources
info "Checking system resources..."
FREE_MB=$(free -m | awk '/^Mem:/{print $4}')
DISK_PCT=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

if [[ "$FREE_MB" -lt 512 ]]; then
    warn "Low memory detected: ${FREE_MB}MB free. Core services might be unstable."
else
    success "Memory: ${FREE_MB}MB free."
fi

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
        if sudo docker ps | grep -q "nexus-n8n"; then
            success "Core service: n8n is running."
        fi
    else
        error "Docker daemon is NOT responding. Try: sudo systemctl restart docker"
    fi
else
    info "Docker not found (Standard behavior for Edge/Mac-Worker nodes)."
fi

# 4. State Verification
if [[ -f ~/.nexus-state ]]; then
    CURRENT_ROLE=$(grep "ROLE=" ~/.nexus-state | cut -d= -f2 || echo "unknown")
    success "Node identity verified: Role is [${CURRENT_ROLE}]."
else
    warn "No state file (~/.nexus-state) found. This node may be unprovisioned."
fi

# 5. Log Health
LOG_FILE="/var/log/nexus/nexus-system.log"
if [[ -f "$LOG_FILE" ]]; then
    ERR_COUNT=$(grep -c "\[ERROR\]" "$LOG_FILE" || echo "0")
    if [[ "$ERR_COUNT" -gt 0 ]]; then
        warn "Found ${ERR_COUNT} error(s) in the system logs. Run: tail -n 20 ${LOG_FILE}"
    else
        success "System logs: Clean (0 errors recently)."
    fi
fi

echo -e "\n${C_BOLD}${C_CYAN}>>> Diagnosis Complete.<<<${C_RESET}\n"
