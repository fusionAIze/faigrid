#!/usr/bin/env bash
TOOL_NAME="mem0"
TOOL_CATEGORY="memory"
TOOL_DESC="Mem0 AI Memory Layer"
TOOL_TYPE="pipx"

tool_install() { pipx install mem0ai; }
tool_update() { pipx upgrade mem0ai; }
tool_status() {
    if pipx list --short | grep -q "^mem0ai "; then echo "Installed"; else echo "Not installed"; fi
}
