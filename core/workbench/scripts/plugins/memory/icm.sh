#!/usr/bin/env bash
TOOL_NAME="icm"
TOOL_CATEGORY="memory"
TOOL_DESC="In-Context Memory (RTK-AI)"
TOOL_TYPE="git"

INSTALL_DIR="/opt/fusionaize-nexus/icm"

tool_install() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        sudo git clone https://github.com/rtk-ai/icm "$INSTALL_DIR"
    fi
}
tool_update() {
    if [[ -d "$INSTALL_DIR" ]]; then cd "$INSTALL_DIR" || exit 1; sudo git pull; fi
}
tool_status() {
    if [[ -d "$INSTALL_DIR" ]]; then echo "Installed"; else echo "Not installed"; fi
}
