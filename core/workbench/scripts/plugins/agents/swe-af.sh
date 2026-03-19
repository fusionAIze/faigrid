#!/usr/bin/env bash
TOOL_NAME="swe-af"
TOOL_CATEGORY="agents"
TOOL_DESC="Agent-Field SWE-AF"
TOOL_TYPE="git"
FAIGATE_CLIENT="swe-af"

INSTALL_DIR="/opt/fusionaize-nexus/swe-af"

tool_install() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        sudo git clone https://github.com/Agent-Field/SWE-AF "$INSTALL_DIR"
    fi
}
tool_update() {
    if [[ -d "$INSTALL_DIR" ]]; then ( cd "$INSTALL_DIR" && sudo git pull ); fi
}
tool_status() {
    if [[ -d "$INSTALL_DIR" ]]; then
        local rev
        rev=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo "Installed (${rev})"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { sudo rm -rf "${INSTALL_DIR}"; }
