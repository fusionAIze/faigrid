#!/usr/bin/env bash
TOOL_NAME="google-ws"
TOOL_CATEGORY="clis"
TOOL_DESC="Google Workspace CLI Toolkit"
TOOL_TYPE="git"
TOOL_UPDATE_TYPE="github"
TOOL_UPDATE_REPO="googleworkspace/cli"

INSTALL_DIR="/opt/faigrid/googleworkspace-cli"

tool_install() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        sudo git clone https://github.com/googleworkspace/cli "$INSTALL_DIR"
    fi
}
tool_update() {
    if [[ -d "$INSTALL_DIR" ]]; then ( cd "$INSTALL_DIR" && sudo git pull ); fi
}
tool_status() {
    if [[ -d "$INSTALL_DIR" ]]; then
        local rev
        rev=$(git -C "$INSTALL_DIR" describe --tags --abbrev=0 2>/dev/null \
            || git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null \
            || echo "unknown")
        echo "Installed (${rev})"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { sudo rm -rf "${INSTALL_DIR}"; }
