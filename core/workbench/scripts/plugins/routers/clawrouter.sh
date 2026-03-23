#!/usr/bin/env bash
TOOL_NAME="clawrouter"
TOOL_CATEGORY="routers"
TOOL_DESC="ClawRouter (BlockRunAI)"
TOOL_TYPE="git"

INSTALL_DIR="/opt/faigrid/clawrouter"

tool_install() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        sudo git clone https://github.com/BlockRunAI/ClawRouter "$INSTALL_DIR"
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
