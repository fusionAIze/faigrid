#!/usr/bin/env bash
TOOL_NAME="n8n"
TOOL_CATEGORY="automation"
TOOL_DESC="n8n Workflow Automation (Core Compose)"
TOOL_TYPE="docker"
TOOL_SERVICE="grid-core-n8n"
FAIGATE_CLIENT="n8n"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

tool_install() {
    if [[ -f "$PROJECT_DIR/core/heart/scripts/install.sh" ]]; then
        bash "$PROJECT_DIR/core/heart/scripts/install.sh"
    fi
}
tool_update() {
    if [[ -f "$PROJECT_DIR/core/heart/scripts/update.sh" ]]; then
        bash "$PROJECT_DIR/core/heart/scripts/update.sh"
    fi
}
tool_uninstall() {
    if [[ -f "$PROJECT_DIR/core/heart/scripts/uninstall.sh" ]]; then
        bash "$PROJECT_DIR/core/heart/scripts/uninstall.sh"
    fi
}
tool_status() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^grid-core-n8n"; then
        local ver
        ver=$(docker inspect grid-core-n8n --format '{{.Config.Image}}' 2>/dev/null | grep -o '[^:]*$' || echo "")
        echo "Installed (Running${ver:+ v${ver}})"
    else
        echo "Not installed"
    fi
}
