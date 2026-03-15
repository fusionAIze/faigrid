#!/usr/bin/env bash

TOOL_NAME="gemini-cli"
TOOL_CATEGORY="clis"
TOOL_DESC="Google Gemini CLI interface"
TOOL_TYPE="pipx"

tool_install() {
    pipx install gemini-cli
}

tool_update() {
    pipx upgrade gemini-cli
}

tool_status() {
    if command -v gemini >/dev/null 2>&1; then
        echo "Installed"
    else
        echo "Not installed"
    fi
}
