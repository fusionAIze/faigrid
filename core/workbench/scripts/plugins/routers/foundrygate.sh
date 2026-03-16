#!/usr/bin/env bash

TOOL_NAME="foundrygate"
TOOL_CATEGORY="routers"
TOOL_DESC="Main AI Routing Gateway (typelicious)"
TOOL_TYPE="git"

INSTALL_DIR="/opt/fusionaize-nexus/foundrygate"

tool_install() {
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "FoundryGate already cloned in $INSTALL_DIR"
    else
        sudo git clone https://github.com/typelicious/FoundryGate "$INSTALL_DIR"
        echo "Check $INSTALL_DIR/README.md for docker launch instructions."
    fi
}

tool_update() {
    if [[ -d "$INSTALL_DIR" ]]; then
        cd "$INSTALL_DIR" || exit 1; sudo git pull
    else
        echo "FoundryGate not found in $INSTALL_DIR."
    fi
}

tool_status() {
    if [[ -d "$INSTALL_DIR" ]]; then
        cd "$INSTALL_DIR" && echo "Installed ($(git rev-parse --short HEAD))"
    else
        echo "Not installed"
    fi
}
