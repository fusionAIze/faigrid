#!/usr/bin/env bash
TOOL_NAME="external-sync"
TOOL_CATEGORY="monitoring"
TOOL_DESC="Cloud-to-Core Sync Monitoring (Nexus External)"
TOOL_TYPE="script"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

tool_status() {
    # Check if we have an external target in .env.topology
    info "Syncing status to cloud..."
    local ext_target=""
    if [[ -f ".env.topology" ]]; then
        ext_target=$(grep "ROLE=external" .env.topology -B 5 | grep "SSH_TARGET" | cut -d'=' -f2 || echo "")
    fi
    
    if [[ -n "$ext_target" ]]; then
        echo "Configured (${ext_target})"
    else
        echo "Not configured"
    fi
}

tool_verify() {
    if [[ -f "$PROJECT_DIR/install.sh" ]]; then
        bash "$PROJECT_DIR/install.sh" --role external --action verify
    fi
}

tool_update() {
    if [[ -f "$PROJECT_DIR/install.sh" ]]; then
        bash "$PROJECT_DIR/install.sh" --role external --action update
    fi
}
