#!/usr/bin/env bash
TOOL_NAME="openrouter"
TOOL_CATEGORY="routers"
TOOL_DESC="OpenRouter CLI integration"
TOOL_TYPE="pipx"

tool_install() { pipx install openrouter-cli; }
tool_update() { pipx upgrade openrouter-cli; }
tool_status() {
    if pipx list --short | grep -q "^openrouter-cli "; then echo "Installed"; else echo "Not installed"; fi
}
