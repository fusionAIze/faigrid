#!/usr/bin/env bash

TOOL_NAME="antigravity"
TOOL_CATEGORY="clis"
TOOL_DESC="Antigravity AI CLI"
TOOL_TYPE="pipx"

tool_install() {
    pipx install antigravity-cli
}
tool_update() {
    pipx upgrade antigravity-cli
}
tool_status() {
    if command -v antigravity >/dev/null 2>&1; then echo "Installed"; else echo "Not installed"; fi
}
