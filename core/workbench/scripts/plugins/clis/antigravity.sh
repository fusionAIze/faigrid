#!/usr/bin/env bash
TOOL_NAME="antigravity"
TOOL_CATEGORY="clis"
TOOL_DESC="Antigravity AI CLI"
TOOL_TYPE="tbd"
# TODO: antigravity appears to be a desktop IDE platform; confirm if a
#       standalone CLI exists and update tool_install/tool_uninstall accordingly.

tool_install() {
    echo "[antigravity] No confirmed CLI install method yet." >&2
    echo "[antigravity] Check https://www.antigravity.dev for CLI docs." >&2
    return 1
}
tool_update() {
    echo "[antigravity] Update not available — install method TBD." >&2
}
tool_status() {
    if command -v antigravity >/dev/null 2>&1; then
        local ver
        ver=$(antigravity --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() {
    echo "[antigravity] Uninstall not available — install method TBD." >&2
}
