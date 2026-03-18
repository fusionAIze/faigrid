#!/usr/bin/env bash
TOOL_NAME="kilo"
TOOL_CATEGORY="clis"
TOOL_DESC="Kilo CLI Agent"
TOOL_TYPE="pipx"

tool_install() { pipx install kilo-ai || echo "Check pipx installation."; }
tool_update()  { pipx upgrade kilo-ai; }
tool_status() {
    if command -v kilo >/dev/null 2>&1; then
        local ver
        ver=$(kilo --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { pipx uninstall kilo-ai; }
