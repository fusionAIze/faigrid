#!/usr/bin/env bash
TOOL_NAME="deepseek"
TOOL_CATEGORY="clis"
TOOL_DESC="Unofficial DeepSeek CLI"
TOOL_TYPE="npm"

tool_install() { npm install -g deepseek-cli; }
tool_update()  { npm update -g deepseek-cli; }
tool_status() {
    if command -v deepseek >/dev/null 2>&1; then
        local ver
        ver=$(deepseek --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { npm uninstall -g deepseek-cli; }
