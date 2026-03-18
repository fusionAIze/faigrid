#!/usr/bin/env bash
TOOL_NAME="mem0"
TOOL_CATEGORY="memory"
TOOL_DESC="Mem0 AI Memory Layer"
TOOL_TYPE="pipx"

tool_install()   { pipx install mem0ai; }
tool_update()    { pipx upgrade mem0ai; }
tool_status() {
    local ver
    ver=$(pipx list --short 2>/dev/null | awk '/^mem0ai /{print $2}')
    if [[ -n "$ver" ]]; then echo "Installed (${ver})"; else echo "Not installed"; fi
}
tool_uninstall() { pipx uninstall mem0ai; }
