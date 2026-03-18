#!/usr/bin/env bash
TOOL_NAME="codex"
TOOL_CATEGORY="clis"
TOOL_DESC="OpenAI Codex CLI interface"
TOOL_TYPE="npm"

tool_install() {
    npm install -g openai-codex-cli
}
tool_update() {
    npm update -g openai-codex-cli
}
tool_status() {
    if command -v codex >/dev/null 2>&1; then
        local ver
        ver=$(codex --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { npm uninstall -g openai-codex-cli; }
