#!/usr/bin/env bash
TOOL_NAME="google-ws"
TOOL_CATEGORY="clis"
TOOL_DESC="Google Workspace CLI Toolkit"
TOOL_TYPE="git"

INSTALL_DIR="/opt/fusionaize-nexus/googleworkspace-cli"

tool_install() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        sudo git clone https://github.com/googleworkspace/cli "$INSTALL_DIR"
    fi
}
tool_update() {
    if [[ -d "$INSTALL_DIR" ]]; then cd "$INSTALL_DIR" || exit 1; sudo git pull; fi
}
tool_status() {
    if [[ -d "$INSTALL_DIR" ]]; then echo "Installed"; else echo "Not installed"; fi
}
