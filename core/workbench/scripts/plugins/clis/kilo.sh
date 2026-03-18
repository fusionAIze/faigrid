#!/usr/bin/env bash
TOOL_NAME="kilo"
TOOL_CATEGORY="clis"
TOOL_DESC="Kilo Code CLI Agent (OpenCode fork)"
TOOL_TYPE="npm"

tool_install() {
    sudo npm install -g @kilocode/cli || echo "Please check npm configuration."
}
tool_update() {
    sudo npm update -g @kilocode/cli
}
tool_status() {
    if command -v kilo >/dev/null 2>&1; then
        local ver
        ver=$(kilo --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { sudo npm uninstall -g @kilocode/cli; }
