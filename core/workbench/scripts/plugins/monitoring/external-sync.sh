#!/usr/bin/env bash
TOOL_NAME="external-sync"
TOOL_CATEGORY="monitoring"
TOOL_DESC="Cloud-to-Core Sync Monitoring (Grid External)"
TOOL_TYPE="script"
TOOL_MANAGED="auto"   # activated by orchestrator, not manually installable

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

tool_install() {
    # external-sync has no automated install — it activates when a grid-external node is registered
    echo "[external-sync] No automated install. Add a grid-external node via the orchestrator to activate." >&2
}

tool_status() {
    # Check if we have an external target in .env.topology
    local ext_target=""
    if [[ -f ".env.topology" ]]; then
        ext_target=$(grep "ROLE=external" .env.topology -B 5 | grep "SSH_TARGET" | cut -d'=' -f2 || echo "")
    fi

    if [[ -n "$ext_target" ]]; then
        echo "Configured (${ext_target})"
    else
        echo "Not installed"
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
