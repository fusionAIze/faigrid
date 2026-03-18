#!/usr/bin/env bash
TOOL_NAME="openrouter"
TOOL_CATEGORY="routers"
TOOL_DESC="OpenRouter CLI integration"
TOOL_TYPE="pipx"

tool_install()   { pipx install openrouter-cli; }
tool_update()    { pipx upgrade openrouter-cli; }
tool_status() {
    local ver
    ver=$(pipx list --short 2>/dev/null | awk '/^openrouter-cli /{print $2}')
    if [[ -n "$ver" ]]; then echo "Installed (${ver})"; else echo "Not installed"; fi
}
tool_uninstall() { pipx uninstall openrouter-cli; }
