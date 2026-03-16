#!/usr/bin/env bash
TOOL_NAME="deepseek"
TOOL_CATEGORY="clis"
TOOL_DESC="Unofficial DeepSeek CLI"
TOOL_TYPE="npm"

tool_install() { npm install -g deepseek-cli; }
tool_update() { npm update -g deepseek-cli; }
tool_status() {
    if command -v deepseek >/dev/null 2>&1; then echo "Installed"; else echo "Not installed"; fi
}
