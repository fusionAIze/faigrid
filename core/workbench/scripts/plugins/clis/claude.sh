#!/usr/bin/env bash

TOOL_NAME="claude-cli"
TOOL_CATEGORY="clis"
TOOL_DESC="Anthropic Claude CLI agent"
TOOL_TYPE="npm"

tool_install() {
    npm install -g @anthropic-ai/claude-cli || echo "Please check npm configuration."
}

tool_update() {
    npm update -g @anthropic-ai/claude-cli
}

tool_status() {
    if command -v claude >/dev/null 2>&1; then
        echo "Installed"
    else
        echo "Not installed"
    fi
}
