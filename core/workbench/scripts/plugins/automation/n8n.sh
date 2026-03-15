#!/usr/bin/env bash
TOOL_NAME="n8n"
TOOL_CATEGORY="automation"
TOOL_DESC="n8n Workflow Automation (Core Compose)"
TOOL_TYPE="docker"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

tool_install() {
    echo "Install via docs/runbooks/step-03-core-heart-stack.md"
}
tool_update() {
    if [[ -f "$PROJECT_DIR/core/heart/scripts/update.sh" ]]; then
        bash "$PROJECT_DIR/core/heart/scripts/update.sh"
    fi
}
tool_status() {
    if docker ps --format '{{.Names}}' | grep -q "^nexus-n8n"; then
        echo "Installed (Running)"
    else
        echo "Not installed"
    fi
}
