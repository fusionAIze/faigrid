#!/usr/bin/env bash
TOOL_NAME="deepseek"
TOOL_CATEGORY="clis"
TOOL_DESC="Unofficial DeepSeek CLI"
TOOL_TYPE="pipx"

_bootstrap_pipx() {
    if ! command -v pipx >/dev/null 2>&1; then
        sudo apt-get install -y pipx 2>/dev/null \
            || sudo python3 -m pip install pipx --break-system-packages
        export PATH="$PATH:$HOME/.local/bin"
        pipx ensurepath 2>/dev/null || true
    fi
}

tool_install() {
    _bootstrap_pipx
    pipx install deepseek-cli
}
tool_update() {
    _bootstrap_pipx
    pipx upgrade deepseek-cli
}
tool_status() {
    if command -v deepseek >/dev/null 2>&1; then
        local ver
        ver=$(deepseek --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { pipx uninstall deepseek-cli 2>/dev/null || true; }
