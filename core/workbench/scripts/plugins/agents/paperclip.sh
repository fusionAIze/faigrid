#!/usr/bin/env bash
TOOL_NAME="paperclip"
TOOL_CATEGORY="agents"
TOOL_DESC="Paperclip AI Agent"
TOOL_TYPE="git"

INSTALL_DIR="/opt/fusionaize-nexus/paperclip"

tool_install() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        sudo git clone https://github.com/paperclipai/paperclip "$INSTALL_DIR"
    fi
}
tool_update() {
    if [[ -d "$INSTALL_DIR" ]]; then cd "$INSTALL_DIR" && sudo git pull; fi
}
tool_status() {
    if [[ -d "$INSTALL_DIR" ]]; then echo "Installed"; else echo "Not installed"; fi
}
