#!/usr/bin/env bash
TOOL_NAME="antigravity"
TOOL_CATEGORY="clis"
TOOL_DESC="Antigravity AI CLI"
TOOL_TYPE="pipx"

tool_install() { pipx install antigravity-cli; }
tool_update()  { pipx upgrade antigravity-cli; }
tool_status() {
    if command -v antigravity >/dev/null 2>&1; then
        local ver
        ver=$(antigravity --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { pipx uninstall antigravity-cli; }
