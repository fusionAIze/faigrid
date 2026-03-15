#!/usr/bin/env bash
TOOL_NAME="cli-anything"
TOOL_CATEGORY="clis"
TOOL_DESC="HKUDS CLI-Anything Toolkit"
TOOL_TYPE="git"

INSTALL_DIR="/opt/fusionaize-nexus/cli-anything"

tool_install() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        sudo git clone https://github.com/HKUDS/CLI-Anything "$INSTALL_DIR"
        echo "Check $INSTALL_DIR/README.md for setup."
    fi
}
tool_update() {
    if [[ -d "$INSTALL_DIR" ]]; then cd "$INSTALL_DIR" && sudo git pull; fi
}
tool_status() {
    if [[ -d "$INSTALL_DIR" ]]; then echo "Installed"; else echo "Not installed"; fi
}
